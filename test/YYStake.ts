import { expect,use } from "chai";
import { ethers } from "hardhat";
import { YYStake,YYToken,STToken } from "../typechain-types";
import { BigNumberish } from "ethers";
import "@nomicfoundation/hardhat-chai-matchers";

describe("YYStake",function() {
    let yytoken:YYToken;
    let sttoken:STToken;
    let yystake:YYStake;
    let owner:any;
    let user1:any;
    let user2:any;
    const defaultEth=ethers.parseEther("10000") as BigNumberish;
    const ZeroAddress=ethers.ZeroAddress;

    beforeEach(async function () {
        [owner,user1,user2]=await ethers.getSigners();

        //部署YYToken代币合约
        const YYTokenFactory=await ethers.getContractFactory("YYToken");
        yytoken=await YYTokenFactory.deploy("YYToken","YY",18,defaultEth)  as YYToken;
        await yytoken.deploymentTransaction()?.wait();
        console.log("YYToken部署成功 address=",await yytoken.target,);
        
        //部署STToken质押代币合约
        const STTokenFactory=await ethers.getContractFactory("STToken");
        sttoken=(await STTokenFactory.deploy("STToken","ST",18,defaultEth))  as STToken;
        await sttoken.deploymentTransaction()?.wait();
        console.log("STToken部署成功 address=",await sttoken.target);

        //部署YYStake合约
        const YYStakeFactory=await ethers.getContractFactory("YYStake");
        yystake=await YYStakeFactory.deploy() as YYStake;
        await yystake.deploymentTransaction()?.wait();

        await yystake.initialize(yytoken.getAddress(),1,100,ethers.parseEther("1"));
        
        // await yytoken.transfer(user.address,ethers.utils.parseEther("100"));
        console.log("YYStake部署成功 address=",await yystake.getAddress());

    });
    
    it("Should deploy and initialize correctly", async function () {
        const totalSupply=await yytoken.totalSupply();
        console.log(totalSupply,defaultEth);
        expect(totalSupply).to.equal(defaultEth);
    });

    it ("Should set the correct YY token address",async () => {
        let currentYYAddress=await yystake.YY();
        console.log(currentYYAddress)
        // await yystake.setYY(await yytoken.getAddress());
        // currentYYAddress=await yystake.YY();
        // console.log(currentYYAddress)
        expect(currentYYAddress).to.equal(yytoken.target);
    });
    
    it("Should assign the correct roles to the deployer", async function () {
        // 检查合约部署者是否被赋予了正确的角色
        expect(await yystake.hasRole(await yystake.DEFAULT_ADMIN_ROLE(), owner.address)).to.be.true;
        expect(await yystake.hasRole(await yystake.UPGRADE_ROLE(), owner.address)).to.be.true;
    });

    
    // it("Should allow admin to add a new staking pool", async function () {
    //     await expect(yystake.addPool(ZeroAddress,100,0,100,true)).to.emit(yystake,"AddPool").withArgs(
    //         ZeroAddress,100,0,100
    //     );
    // });

    
    it("Should allow staking of tokens", async function () {
        // 添加第一个质押池，池子 ID 为 0
        await yystake.addPool(ethers.ZeroAddress, 100, 0, 100, true);
    
        // 添加第二个质押池，池子 ID 为 1
        await yystake.addPool(sttoken.target, 200, ethers.parseUnits("10"), 200, true);

        yytoken.transfer(yystake.target,ethers.parseEther("1000"));
    
        // 将代币转移到 user1 user2
        await sttoken.transfer(user1.address, ethers.parseEther("1000"));
        await sttoken.transfer(user2.address, ethers.parseEther("1000"));

        expect(await sttoken.balanceOf(owner.getAddress())).to.equal(ethers.parseEther("8000"));
        console.log("sttoken balance=",await sttoken.balanceOf(owner.getAddress()));
        console.log("user1 balance=",await sttoken.balanceOf(user1.getAddress()));
        console.log("user2 balance=",await sttoken.balanceOf(user2.getAddress()));

        // // 授权足够的代币给 Stake 合约
        await sttoken.connect(user1).approve(yystake.target, ethers.parseUnits("1000"));
        await sttoken.connect(user2).approve(yystake.target, ethers.parseUnits("1000"));
        
        
        console.log("当前区块高度1=",await ethers.provider.getBlockNumber());
        // // 使用正确的池子 ID 进行质押操作
        await yystake.connect(user1).deposit(1, ethers.parseEther("100"));
        console.log("当前区块高度2=",await ethers.provider.getBlockNumber());
        await yystake.connect(user2).deposit(1, ethers.parseEther("50"));
        console.log("当前区块高度3=",await ethers.provider.getBlockNumber());
        console.log("user1 balance=",await sttoken.balanceOf(user1.getAddress()));
        console.log("user2 balance=",await sttoken.balanceOf(user2.getAddress()));

        // // 检查用户的质押金额是否正确
        const userStake = await yystake.stakingBalance(1,user1.address);
        expect(userStake).to.equal(ethers.parseEther("100"));
        console.log("池1的质押token总数",(await yystake.pools(1)).stTokenAmount);
        console.log("当前区块高度4=",await ethers.provider.getBlockNumber());

        // // user1 解除质押 50 YY
        await yystake.connect(user1).unstake(1, ethers.parseEther("50"));
        // // 检查用户的质押金额是否正确更新
        const userStake1 = await yystake.stakingBalance(1,user1.address);
        expect(userStake1).to.equal(ethers.parseEther("50"));
        console.log("user1的sttoken总数",await sttoken.balanceOf(user1.getAddress()));
        console.log("池1的质押token总数",(await yystake.pools(1)).stTokenAmount);

        console.log("当前区块高度5=",await ethers.provider.getBlockNumber());

        // // 通过人工增加块高或时间来模拟奖励积累
        await ethers.provider.send("evm_increaseTime", [3600]); // 模拟一个小时
        await ethers.provider.send("evm_mine"); // 挖一个区块

        // // addr1 领取奖励
        await yystake.connect(user1).claim(1);
        console.log("当前区块高度6=",await ethers.provider.getBlockNumber());

        // // 检查领取后的状态
        const finalBalance = await yytoken.balanceOf(user1.address);
        console.log("User YY balance after claim:", finalBalance);
        console.log("当前区块高度7=",await ethers.provider.getBlockNumber());

        // // 再次领取奖励，应该没有新增的奖励可领取
        await yystake.connect(user1).claim(1);
        console.log("当前区块高度8=",await ethers.provider.getBlockNumber());
        let newBalance = await yytoken.balanceOf(user1.address);
        console.log("User YY balance after claim2:", newBalance);
        
    });
    
})