# YYStake 质押合约

YYStake是一个基于区块链的质押系统，支持多种代币的质押，配套发行了YYToken代币和STToken代币，并基于用户质押的STToken代币数量和时间长度分配 YY 代币作为奖励。系统可提供多个质押池，每个池可以独立配置质押代币、奖励计算等。

### 角色定义
- **ADMIN_ROLE**: 管理员角色，拥有设置和管理功能的权限。
- **UPGRADE_ROLE**: 升级角色，负责合约的升级操作。


## 使用说明

1. **初始化合约**

   调用 `initialize` 函数来初始化合约，传入 YY 代币地址、起始区块号、结束区块号和每个区块奖励的 YY 数量。

   function initialize(
       IERC20 _YY,
       uint256 _startBlock,
       uint256 _endBlock,
       uint256 _YYPerBlock
   ) public initializer;

2. **存入代币**
    使用 deposit 函数将代币存入合约。此操作将更新用户在指定池中的质押量，并根据权重计算 YY 奖励。

    function deposit(uint256 _pid, uint256 _amount) public;   

3. **存入代币**
    使用 deposit 函数将代币存入合约以获取 YY 奖励。

    function deposit(uint256 _pid, uint256 _amount) public;

4. **请求提取**
    使用 requestUnstake 函数请求提取质押代币。

    function requestUnstake(uint256 _pid, uint256 _amount) public;

5. **领取奖励**
    使用 claim 函数领取 YY 奖励。

    function claim(uint256 _pid) public;
