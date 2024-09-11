// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interface/IERC20.sol";
import "./token/YYToken.sol";

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

contract YYStake is Initializable,UUPSUpgradeable,PausableUpgradeable,AccessControlUpgradeable{
    using Address for address;
    using Math for uint256;

    bytes32 public constant ADMIN_ROLE=keccak256("admin_role");
    bytes32 public constant UPGRADE_ROLE = keccak256("upgrade_role");
    
    uint256 public constant nativeCurrency_PID = 0;

    struct Pool {
        address stTokenAddress;
        uint256 poolWeight;
        uint256 lastRewardBlock;
        uint256 accYYPerST;
        uint256 stTokenAmount;
        uint256 minDepositAmount;
        uint256 unstakeLockedBlocks;
    }

    struct UnstakeRequest{
        uint256 amount;
        uint256 unlockBlocks;
    }

    struct User {
        uint256 stAmount;
        uint256 finishedYY;
        uint256 pendingYY;
        UnstakeRequest[] requests;
    }

    uint256 public startBlock;
    uint256 public endBlock;
    uint256 public YYPerBlock;

    bool public withdrawPaused;
    bool public claimPaused;

    //YYToken
    IERC20 public YY;

    uint256 public totalPoolWeight;
    Pool[] public pools;

    mapping (uint256 => mapping (address => User)) public users;

    event SetYY(IERC20 indexed YY);

    event PauseWithdraw();
    event UnpauseWithdraw();
    event PauseClaim();
    event UnpauseClaim();
    event SetStartBlock(uint256 indexed startBlock);
    event SetEndBlock(uint256 indexed endBlock);
    event SetYYPerBlock(uint256 indexed YYPerBlock);
    event AddPool(address indexed stTokenAddress,uint256 indexed poolWeight,uint256 minDepositAmount,uint256 unstakeLockedBlocks);
    event UpdatePoolInfo(uint256 indexed minDepositAmount,uint256 indexed unstakeLockedBlocks);
    
    event SetPoolWeight(
        uint256 indexed poolId,
        uint256 indexed poolWeight,
        uint256 totalPoolWeight
    );
    
    event UpdatePool(
        uint256 indexed poolId,
        uint256 indexed lastRewardBlock,
        uint256 totalYY
    );
    
    event Deposit(address indexed user, uint256 indexed poolId, uint256 amount);


    event RequestUnstake(
        address indexed user,
        uint256 indexed poolId,
        uint256 amount
    );

    event Withdraw(
        address indexed user,
        uint256 indexed poolId,
        uint256 amount,
        uint256 indexed blockNumber
    );

    event Claim(
        address indexed user,
        uint256 indexed poolId,
        uint256 YYReward
    );

    modifier checkPid(uint256 _pid) {
        require(_pid<pools.length,"invalid pid");
        _;
    }

    modifier whenNotClaimPaused(){
        require(!claimPaused,"claim is paused");
        _;
    }

    modifier whenNotWithdrawPaused() {
        require(!withdrawPaused, "withdraw is paused");
        _;
    }

    function initialize(
        IERC20 _YY,uint256 _starkBlock,uint256 _endBlock,uint256 _YYPerBlock
    ) public initializer {
        require(_starkBlock<=_endBlock && _YYPerBlock>0,"invalid parameters");
        __AccessControl_init();
        __UUPSUpgradeable_init();
        _grantRole(DEFAULT_ADMIN_ROLE,msg.sender);
        _grantRole(UPGRADE_ROLE,msg.sender);
        _grantRole(ADMIN_ROLE,msg.sender);

        setYY(_YY);

        startBlock=_starkBlock;
        endBlock=_endBlock;
        YYPerBlock=_YYPerBlock;
    }

    function _authorizeUpgrade(address newImplementtation) internal override onlyRole(UPGRADE_ROLE){}

    function setYY(IERC20 _YY) public onlyRole(ADMIN_ROLE){
        YY=_YY;
        emit SetYY(_YY);
    }

    function pauseWithdraw() public onlyRole(ADMIN_ROLE) {
        require(!withdrawPaused,"withdraw has been already paused");
        withdrawPaused=true;
        emit PauseWithdraw();
    }

    function uppauseWithdraw() public onlyRole(ADMIN_ROLE){
        require(withdrawPaused,"withdraw has been already unpaused");
        withdrawPaused=false;
    
        emit UnpauseWithdraw();
    }

    function pauseClaim() public onlyRole(ADMIN_ROLE) {
        require(!claimPaused, "claim has been already paused");

        claimPaused = true;

        emit PauseClaim();
    }

    function unpauseClaim() public onlyRole(ADMIN_ROLE) {
        require(claimPaused, "claim has been already unpaused");

        claimPaused = false;

        emit UnpauseClaim();
    }
    
    function setStartBlock(uint256 _startBlock) public onlyRole(ADMIN_ROLE) {
        require(
            _startBlock <= endBlock,
            "start block must be smaller than end block"
        );

        startBlock = _startBlock;

        emit SetStartBlock(_startBlock);
    }

    function setEndBlock(uint256 _endBlock) public {
        require(
            startBlock <= _endBlock,
            "start block must be smaller than end block"
        );

        endBlock = _endBlock;

        emit SetEndBlock(_endBlock);
    }

    function setYYPerBlock(uint256 _YYPerBlock) public onlyRole(ADMIN_ROLE) {
        require(_YYPerBlock > 0, "invalid parameter");

        YYPerBlock = _YYPerBlock;

        emit SetYYPerBlock(_YYPerBlock);
    }

    function getBlockNumber() public view returns(uint){
        return block.number;
    }

    function addPool(address _stTokenAddress,uint256 _poolWeight,uint256 _minDepositAmount,uint256 _unstakeLockedBlocks,bool _withUpdate) public onlyRole(ADMIN_ROLE) {
        // require(false,_stTokenAddress);
        if(pools.length>0){
            require(_stTokenAddress!=address(0x0),"invalid staking token address1");
        }else{
            require(_stTokenAddress == address(0x0),"invalid staking token address2");
            // require(_stTokenAddress == address(0x0), string(abi.encodePacked("invalid staking token address2: ", _stTokenAddress)));

        }

        // allow the min deposit amount equal to 0
        //require(_minDepositAmount > 0, "invalid min deposit amount");
        require(_unstakeLockedBlocks > 0, "invalid withdraw locked blocks");
        require(block.number < endBlock, "Already ended");

        if(_withUpdate){
            massUpdatePools();
        }

        uint256 lastRewardBlock=block.number>startBlock?block.number:startBlock;
        totalPoolWeight=totalPoolWeight+_poolWeight;
        pools.push(Pool({
            stTokenAddress:_stTokenAddress,
            poolWeight:_poolWeight,
            lastRewardBlock:lastRewardBlock,
            accYYPerST:0,
            stTokenAmount:0,
            minDepositAmount:_minDepositAmount,
            unstakeLockedBlocks:_unstakeLockedBlocks
        }));
        emit AddPool(_stTokenAddress,_poolWeight,_minDepositAmount,_unstakeLockedBlocks);
    }

    function massUpdatePools() public {
        uint256 length = pools.length;
        for (uint256 pid = 0; pid < length; pid++) {
            updatePool(pid);
        }
    }
    
    function updatePool(uint256 _pid) public checkPid(_pid) {
        Pool storage pool_ = pools[_pid];

        if (block.number <= pool_.lastRewardBlock) {
            return;
        }

        (bool success1, uint256 totalYY) = getMultiplier(
            pool_.lastRewardBlock,
            block.number
        ).tryMul(pool_.poolWeight);
        require(success1, "totalYY mul poolWeight overflow");

        (success1, totalYY) = totalYY.tryDiv(totalPoolWeight);
        require(success1, "totalYY div totalPoolWeight overflow");

        uint256 stSupply = pool_.stTokenAmount;
        if (stSupply > 0) {
            (bool success2, uint256 totalYY_) = totalYY.tryMul(1 ether);
            require(success2, "totalYY mul 1 ether overflow");

            (success2, totalYY_) = totalYY_.tryDiv(stSupply);
            require(success2, "totalYY div stSupply overflow");

            (bool success3, uint256 accYYPerST) = pool_.accYYPerST.tryAdd(
                totalYY_
            );
            require(success3, "pool accYYPerST overflow");
            pool_.accYYPerST = accYYPerST;
        }

        pool_.lastRewardBlock = block.number;

        emit UpdatePool(_pid, pool_.lastRewardBlock, totalYY);
    }
    
    function getMultiplier(
        uint256 _from,
        uint256 _to
    ) public view returns (uint256 multiplier) {
        require(_from <= _to, "invalid block range");
        if (_from < startBlock) {
            _from = startBlock;
        }
        if (_to > endBlock) {
            _to = endBlock;
        }
        require(_from <= _to, "end block must be greater than start block");
        bool success;
        (success, multiplier) = (_to - _from).tryMul(YYPerBlock);
        require(success, "multiplier overflow");
    }

    function setPoolWeight(uint256 _pid,uint256 _poolWeight,bool _withUpdate) public onlyRole(ADMIN_ROLE) checkPid(_pid){
        require(_poolWeight>0,"invalid pool weight");
        if(_withUpdate){
            massUpdatePools();
        }

        totalPoolWeight=totalPoolWeight-pools[_pid].poolWeight+_poolWeight;
        pools[_pid].poolWeight=_poolWeight;
        emit SetPoolWeight(_pid,_poolWeight,totalPoolWeight);
    }

    function poolLength() external view returns(uint256){
        return pools.length;
    }

    function pendingYY(uint256 _pid,address _user) external view checkPid(_pid) returns(uint256){
        return pendingYYByBlockNumber(_pid, _user, block.number);
    }
    function pendingYYByBlockNumber(uint256 _pid,address _user,uint256 _blockNumber) public view checkPid(_pid) returns(uint256) {
        Pool storage pool_=pools[_pid];
        User storage user_=users[_pid][_user];
        uint256 accYYPerST=pool_.accYYPerST;
        uint256 stSupply=pool_.stTokenAmount;
        if(_blockNumber>pool_.lastRewardBlock && stSupply!=0){
            uint256 multiplier=getMultiplier(pool_.lastRewardBlock,_blockNumber);
            uint256 YYForPool=(multiplier* pool_.poolWeight)/totalPoolWeight;
            accYYPerST=accYYPerST+(YYForPool*(1 ether))/stSupply;
        }
        return (user_.stAmount*accYYPerST)/(1 ether)-user_.finishedYY+user_.pendingYY;
    }

    function stakingBalance(uint256 _pid,address _user) external view checkPid(_pid) returns (uint256){
        return users[_pid][_user].stAmount;
    }

    function withdrawAmount(uint256 _pid,address _user) public view checkPid(_pid) returns(uint256 requestAmount,uint256 pendingWithdrawAmount){
        User storage user_=users[_pid][_user];
        for(uint256 i=0;i<user_.requests.length;i++){
            if(user_.requests[i].unlockBlocks<=block.number){
                pendingWithdrawAmount+=user_.requests[i].amount;
            }
            requestAmount+=user_.requests[i].amount;
        }
    }

    function depositnativeCurrency() public payable whenNotPaused {
        Pool storage pool_=pools[nativeCurrency_PID];
        require(pool_.stTokenAddress==address(0x0),"invalid staking token address");
        uint256 _amount=msg.value;
        require(_amount>=pool_.minDepositAmount,"deposit amount is tool small");
        _deposit(nativeCurrency_PID,_amount);
    }

    function deposit(uint256 _pid,uint256 _amount) public whenNotPaused() checkPid(_pid){
        // 检查是否是有效的池子ID（0表示不支持原生币质押）
        require(_pid != 0, "deposit not support nativeCurrency staking");

        Pool storage pool_ = pools[_pid];

        require(_amount >= pool_.minDepositAmount, "deposit amount is too small");

        // 如果存款金额大于0，则从用户地址将指定数量的质押代币转移到合约地址
        if(_amount > 0){
            IERC20(pool_.stTokenAddress).transferFrom(msg.sender, address(this), _amount);
        }
        // 调用内部函数进行存款处理，传入池子ID（_pid）和存款金额（_amount）
        _deposit(_pid,_amount);
    }

    function _deposit(uint256 _pid, uint256 _amount) internal {
        Pool storage pool_ = pools[_pid];
        User storage user_ = users[_pid][msg.sender];

        updatePool(_pid);
        if (user_.stAmount > 0) {
            // uint256 accST = user_.stAmount.mulDiv(pool_.accYYPerST, 1 ether);
            (bool success1, uint256 accST) = user_.stAmount.tryMul(
                pool_.accYYPerST
            );
            require(success1, "user stAmount mul accYYPerST overflow");
            (success1, accST) = accST.tryDiv(1 ether);
            require(success1, "accST div 1 ether overflow");

            (bool success2, uint256 pendingYY_) = accST.trySub(
                user_.finishedYY
            );
            require(success2, "accST sub finisheYY overflow");
            if (pendingYY_ > 0) {
                (bool success3, uint256 _pendingYY) = user_.pendingYY.tryAdd(
                    pendingYY_
                );
                require(success3, "user pendingYY overflow");
                user_.pendingYY = _pendingYY;
            }
        }

        if (_amount > 0) {
            (bool success4, uint256 stAmount) = user_.stAmount.tryAdd(_amount);
            require(success4, "user stAmount overflow");
            user_.stAmount = stAmount;
        }

        (bool success5, uint256 stTokenAmount) = pool_.stTokenAmount.tryAdd(
            _amount
        );
        require(success5, "pool stTokenAmount overflow");
        pool_.stTokenAmount = stTokenAmount;

        // user_.finisheYY = user_.stAmount.mulDiv(pool_.accYYPerST, 1 ether);
        (bool success6, uint256 finisheYY) = user_.stAmount.tryMul(
            pool_.accYYPerST
        );
        require(success6, "user stAmount mul accYYPerST overflow");

        (success6, finisheYY) = finisheYY.tryDiv(1 ether);
        require(success6, "finisheYY div 1 ether overflow");

        user_.finishedYY = finisheYY;

        emit Deposit(msg.sender, _pid, _amount);
    }


    function unstake(
        uint256 _pid,
        uint256 _amount
    ) public whenNotPaused checkPid(_pid) whenNotWithdrawPaused {
        Pool storage pool_ = pools[_pid];
        User storage user_ = users[_pid][msg.sender];

        require(user_.stAmount >= _amount, "Not enough staking token balance");

        updatePool(_pid);

        uint256 pendingYY_ = (user_.stAmount * pool_.accYYPerST) /
            (1 ether) -
            user_.finishedYY;

        if (pendingYY_ > 0) {
            user_.pendingYY = user_.pendingYY + pendingYY_;
        }

        if (_amount > 0) {
            user_.stAmount = user_.stAmount - _amount;
            user_.requests.push(
                UnstakeRequest({
                    amount: _amount,
                    unlockBlocks: block.number + pool_.unstakeLockedBlocks
                })
            );
        }

        pool_.stTokenAmount = pool_.stTokenAmount - _amount;
        user_.finishedYY = (user_.stAmount * pool_.accYYPerST) / (1 ether);

        emit RequestUnstake(msg.sender, _pid, _amount);
    }

    
    function withdraw(
        uint256 _pid
    ) public whenNotPaused checkPid(_pid) whenNotWithdrawPaused {
        Pool storage pool_ = pools[_pid];
        User storage user_ = users[_pid][msg.sender];

        uint256 pendingWithdraw_;
        uint256 popNum_;
        for (uint256 i = 0; i < user_.requests.length; i++) {
            if (user_.requests[i].unlockBlocks > block.number) {
                break;
            }
            pendingWithdraw_ = pendingWithdraw_ + user_.requests[i].amount;
            popNum_++;
        }

        for (uint256 i = 0; i < user_.requests.length - popNum_; i++) {
            user_.requests[i] = user_.requests[i + popNum_];
        }

        for (uint256 i = 0; i < popNum_; i++) {
            user_.requests.pop();
        }

        if (pendingWithdraw_ > 0) {
            if (pool_.stTokenAddress == address(0x0)) {
                _safenativeCurrencyTransfer(msg.sender, pendingWithdraw_);
            } else {
                IERC20(pool_.stTokenAddress).transfer(
                    msg.sender,
                    pendingWithdraw_
                );
            }
        }

        emit Withdraw(msg.sender, _pid, pendingWithdraw_, block.number);
    }
    function claim(
        uint256 _pid
    ) public whenNotPaused checkPid(_pid) whenNotClaimPaused {
        Pool storage pool_ = pools[_pid];
        User storage user_ = users[_pid][msg.sender];

        updatePool(_pid);

        uint256 pendingYY_ = (user_.stAmount * pool_.accYYPerST) /
            (1 ether) -
            user_.finishedYY +
            user_.pendingYY;

        if (pendingYY_ > 0) {
            user_.pendingYY = 0;
            _safeYYTransfer(msg.sender, pendingYY_);
        }

        user_.finishedYY = (user_.stAmount * pool_.accYYPerST) / (1 ether);

        emit Claim(msg.sender, _pid, pendingYY_);
    }

    function _safeYYTransfer(address _to, uint256 _amount) internal {
        uint256 YYBal = YY.balanceOf(address(this));
        if (_amount > YYBal) {
            YY.transfer(_to, YYBal);
        } else {
            YY.transfer(_to, _amount);
        }
    }
    
    function _safenativeCurrencyTransfer(
        address _to,
        uint256 _amount
    ) internal {
        (bool success, bytes memory data) = address(_to).call{value: _amount}(
            ""
        );

        require(success, "nativeCurrency transfer call failed");
        if (data.length > 0) {
            require(
                abi.decode(data, (bool)),
                "nativeCurrency transfer operation did not succeed"
            );
        }
    }

    function debug(uint256 msg1,uint256 msg2) internal view {
        debug(string(abi.encodePacked(Strings.toString(msg1),"-",Strings.toString(msg2))));
    }
    function debug(uint256 msg1,uint256 msg2,uint256 msg3) internal view {
        debug(string(abi.encodePacked(Strings.toString(msg1),"-",Strings.toString(msg2),"-",Strings.toString(msg3))));
    }
    function debug(uint256 tip) internal view {
        debug(Strings.toString(tip),"");
    }
    function debug(string memory tip) internal view {
        debug(tip,"");
    }
    function debug(string memory tip,string memory msg1) internal view {
        revert(string(abi.encodePacked(tip,msg1)));
    }
    function debug(string memory tip,uint256 msg1) internal view {
        debug(tip,Strings.toString(msg1));
    }

}