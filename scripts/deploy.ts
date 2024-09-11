import { ethers } from "hardhat";

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer.address);
    console.log("Account balance:", (await deployer.provider.getBalance(deployer.address)).toString());


    // 部署 YYToken 代币合约
    const YYToken = await ethers.getContractFactory("YYToken");
    const yytoken = await YYToken.deploy("YYToken", "YY", 18, ethers.parseEther("1000000"));
    await yytoken.deploymentTransaction()?.wait();
    console.log("YYToken deployed to:", yytoken.target);
    
    // 部署 STToken 质押代币合约
    const STToken = await ethers.getContractFactory("STToken");
    const sttoken = await YYToken.deploy("STToken", "ST", 18, ethers.parseEther("1000000"));
    await sttoken.deploymentTransaction()?.wait();
    console.log("STToken deployed to:", sttoken.target);


    // 部署 YYStake 合约
    const YYStake = await ethers.getContractFactory("YYStake");
    const yystake = await YYStake.deploy();
    await yystake.deploymentTransaction()?.wait();

    console.log("YYStake deployed to:", yystake.target);

}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});