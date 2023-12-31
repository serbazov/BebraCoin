/*
  be shure, to hardhat-config is properly configured
  run: npx hardhat test
*/
const { keccak256 } = require("@ethersproject/keccak256");
const { toUtf8Bytes } = require("@ethersproject/strings");
const {
  time,
  loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { ethers } = require("hardhat");
const BigNumber = require("ethers");
// const comptrollerAddress = "0xDb0C52f1F3892e179a69b19aa25dA2aECe5006ac";
const comptrollerAddress = "0x60CF091cD3f50420d50fD7f707414d0DF4751C58";
// const veloRouterAddress = "0x9c12939390052919af3155f41bf4160fd3666a6f";
const veloRouterAddress = "0xa062aE8A9c5e11aaA026fc2670B0D65cCc8B2858";
const veloTokenAddress = "0x3c8B650257cFb5f272f799F5e2b4e65093a11a05";
const SONNEaddress = "0x1DB2466d9F5e10D7090E7152B68d62703a2245F0";
const unitrollerAddress = "0x60CF091cD3f50420d50fD7f707414d0DF4751C58";
const veloFactory = "0xF1046053aa5682b4F9a81b5481394DA16BE5FF5a";
const DAIaddress = "0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1";
const WETHaddress = "0x4200000000000000000000000000000000000006";
const soDAIaddress = "0x5569b83de187375d43FBd747598bfe64fC8f6436";
const soUSDCAddress = "0xEC8FEa79026FfEd168cCf5C627c7f486D77b765F";
const soWETHAddress = "0xf7B5965f5C117Eb1B5450187c9DcFccc3C317e8E";
const soOPAddress = "0x8cD6b19A07d754bF36AdEEE79EDF4F2134a8F571";
const OPUSDCPoolToken = "0x0df083de449F75691fc5A36477a6f3284C269108";
const OPUSDCGauge = "0x36691b39Ec8fa915204ba1e1A4A3596994515639";
const WETHUSDCPoolToken = "0x0493Bf8b6DBB159Ce2Db2E0E8403E753Abd1235b";
const WETHUSDCGauge = "0xE7630c9560C59CCBf5EEd8f33dd0ccA2E67a3981";
const priceOracleAddress = "0xEFc0495DA3E48c5A55F73706b249FD49d711A502";
const USDCAddress = "0x7F5c764cBc14f9669B88837ca1490cCa17c31607";

describe("Bebra Coin", function () {
  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.
  async function deployManagerFixture() {
    const WETHabi = require("../abi/wETHabi.json");
    const soWETHabi = require("../abi/sowETHabi.json");
    const DAIabi = require("../abi/DAIabi.json");
    const usdcABI = require("../abi/usdcABI.json");

    const [owner, otherAccount] = await ethers.getSigners();

    // const compabi = require('../abi/comptrollerABI.json');
    // const comp = new ethers.Contract(comptrollerAddress, compabi);
    // console.log(await comp.connect(owner).markets(soWETHaddress));

    // Contracts are deployed using the first signer/account by default
    const posManager = await ethers.getContractFactory("DNSPositionManager");
    const posManagercontract = await posManager.deploy(
      [
        SONNEaddress,
        comptrollerAddress,
        veloRouterAddress,
        unitrollerAddress,
        OPUSDCPoolToken,
        soUSDCAddress,
        soOPAddress,
        priceOracleAddress,
        USDCAddress,
        veloFactory,
        OPUSDCGauge,
      ],
      [
        ethers.parseEther("0.65"),
        ethers.parseEther("1.2"),
        ethers.parseEther("1.3"),
        ethers.parseEther("1.1"),
      ]
    );
    await posManagercontract.waitForDeployment();

    const posManagercontract1 = await posManager.deploy(
      [
        SONNEaddress,
        comptrollerAddress,
        veloRouterAddress,
        unitrollerAddress,
        WETHUSDCPoolToken,
        soUSDCAddress,
        soWETHAddress,
        priceOracleAddress,
        USDCAddress,
        veloFactory,
        WETHUSDCGauge,
      ],
      [
        ethers.parseEther("0.75"),
        ethers.parseEther("1.2"),
        ethers.parseEther("1.3"),
        ethers.parseEther("1.1"),
      ]
    );
    await posManagercontract1.waitForDeployment();
    const strategyManager = await ethers.getContractFactory("StrategyManager");
    const strategyManagercontract = await strategyManager.deploy();
    await strategyManagercontract.waitForDeployment();
    await posManagercontract
      .connect(owner)
      .grantRole(
        keccak256(toUtf8Bytes("STRATEGIES_MANAGER_ROLE")),
        strategyManagercontract.target
      );
    await posManagercontract1
      .connect(owner)
      .grantRole(
        keccak256(toUtf8Bytes("STRATEGIES_MANAGER_ROLE")),
        strategyManagercontract.target
      );
    // get some WETH to supply
    const WETH = new ethers.Contract(WETHaddress, WETHabi);
    await WETH.connect(owner).deposit({ value: ethers.parseEther("10") });
    await WETH.connect(otherAccount).deposit({
      value: ethers.parseEther("10"),
    });
    const USDC = new ethers.Contract(USDCAddress, usdcABI);

    const abi = require("../abi/veloRouter.json");
    const router = new ethers.Contract(veloRouterAddress, abi);
    let routes = [
      {
        from: WETH.target,
        to: USDC.target,
        stable: false,
        factory: veloFactory,
      },
    ];
    await WETH.connect(owner).approve(
      router.target,
      ethers.parseEther("1").toString()
    );
    await router
      .connect(owner)
      .swapExactTokensForTokens(
        ethers.parseEther("1"),
        0,
        routes,
        owner.address,
        Math.floor(Date.now() / 1000) + 60,
        { gasLimit: 20000000 }
      );
    await WETH.connect(otherAccount).approve(
      router.target,
      ethers.parseEther("1").toString()
    );
    await router
      .connect(otherAccount)
      .swapExactTokensForTokens(
        ethers.parseEther("1"),
        0,
        routes,
        otherAccount.address,
        Math.floor(Date.now() / 1000) + 60,
        { gasLimit: 20000000 }
      );

    return {
      posManagercontract,
      strategyManagercontract,
      USDC,
      owner,
      otherAccount,
      veloRouterAddress,
      SONNEaddress,
      veloTokenAddress,
      posManagercontract1,
    };
  }

  describe("base functions", function () {
    describe("not revert validations", function () {
      it("changeStrategies", async function () {
        const {
          posManagercontract,
          owner,
          strategyManagercontract,
          posManagercontract1,
        } = await loadFixture(deployManagerFixture);

        await expect(
          await strategyManagercontract
            .connect(owner)
            .changeStrategies(
              [posManagercontract.target, posManagercontract1.target],
              [ethers.parseEther("0.5"), ethers.parseEther("0.5")]
            )
        )
          .to.emit(strategyManagercontract, "StrategiesChanged")
          .withArgs(
            [posManagercontract.target, posManagercontract1.target],
            [ethers.parseEther("0.5"), ethers.parseEther("0.5")]
          );
      });
      it("deposit", async function () {
        const {
          posManagercontract,
          owner,
          strategyManagercontract,
          USDC,
          posManagercontract1,
        } = await loadFixture(deployManagerFixture);
        // console.log(await contract.connect(owner).getAccountSnapshot());
        await USDC.connect(owner).approve(
          strategyManagercontract.target,
          ethers.parseUnits("10", 6)
        );
        await strategyManagercontract
          .connect(owner)
          .changeStrategies(
            [posManagercontract.target, posManagercontract1.target],
            [ethers.parseEther("0.5"), ethers.parseEther("0.5")]
          );
        await expect(
          await strategyManagercontract
            .connect(owner)
            .deposit(ethers.parseUnits("10", 6))
        )
          .to.emit(strategyManagercontract, "Deposit")
          .withArgs(owner.address, ethers.parseUnits("10", 6));
        await expect(
          await strategyManagercontract.connect(owner).getTotalPooledAmount()
        ).not.to.be.reverted;
        // console.log(
        //   await posManagercontract.connect(owner).getAccountSnapshot()
        // );
        // console.log(
        //   await posManagercontract1.connect(owner).getAccountSnapshot()
        // );
      });
      it("withdraw", async function () {
        const {
          posManagercontract,
          owner,
          strategyManagercontract,
          USDC,
          posManagercontract1,
        } = await loadFixture(deployManagerFixture);
        // console.log(await contract.connect(owner).getAccountSnapshot());
        await USDC.connect(owner).approve(
          strategyManagercontract.target,
          ethers.parseUnits("10", 6)
        );
        await strategyManagercontract
          .connect(owner)
          .changeStrategies(
            [posManagercontract.target, posManagercontract1.target],
            [ethers.parseEther("0.5"), ethers.parseEther("0.5")]
          );
        await expect(
          await strategyManagercontract
            .connect(owner)
            .deposit(ethers.parseUnits("10", 6))
        )
          .to.emit(strategyManagercontract, "Deposit")
          .withArgs(owner.address, ethers.parseUnits("10", 6));
        await expect(
          await strategyManagercontract.connect(owner).getTotalPooledAmount()
        ).not.to.be.reverted;
        await expect(
          await strategyManagercontract
            .connect(owner)
            .closePosition(ethers.parseUnits("5", 6))
        )
          .to.emit(strategyManagercontract, "Withdraw")
          .withArgs(owner.address, ethers.parseUnits("5", 6));
        // console.log(
        //   await strategyManagercontract.connect(owner).getTotalPooledAmount()
        // );
        // console.log(
        //   await strategyManagercontract.connect(owner).balanceOf(owner.address)
        // );
      });
      it("harvest", async function () {
        const {
          posManagercontract,
          owner,
          strategyManagercontract,
          USDC,
          otherAccount,
          posManagercontract1,
        } = await loadFixture(deployManagerFixture);
        // console.log(await contract.connect(owner).getAccountSnapshot());
        await USDC.connect(owner).approve(
          strategyManagercontract.target,
          ethers.parseUnits("10", 6)
        );
        await USDC.connect(otherAccount).approve(
          strategyManagercontract.target,
          ethers.parseUnits("10", 6)
        );
        await strategyManagercontract
          .connect(owner)
          .changeStrategies(
            [posManagercontract.target, posManagercontract1.target],
            [ethers.parseEther("0.5"), ethers.parseEther("0.5")]
          );
        await expect(
          await strategyManagercontract
            .connect(owner)
            .deposit(ethers.parseUnits("10", 6))
        )
          .to.emit(strategyManagercontract, "Deposit")
          .withArgs(owner.address, ethers.parseUnits("10", 6));
        // await console.log(
        //   "otherAccount balance",
        //   await USDC.connect(otherAccount).balanceOf(otherAccount)
        // );
        await strategyManagercontract
          .connect(otherAccount)
          .deposit(ethers.parseUnits("5", 6));
        await expect(
          await strategyManagercontract.connect(owner).getTotalPooledAmount()
        ).not.to.be.reverted;
        // console.log(
        //   "totalAmountBeforeHarvest",
        //   await strategyManagercontract.connect(owner).getTotalPooledAmount()
        // );
        // console.log(
        //   "OwnerAmountBeforeHarvest",
        //   await strategyManagercontract.connect(owner).balanceOf(owner.address)
        // );
        // console.log(
        //   "StrategyBalanceBeforeHarvest",
        //   await posManagercontract.connect(owner).getTotalAmount()
        // );
        // console.log(
        //   "StrategyBalanceBeforeHarvest1",
        //   await posManagercontract1.connect(owner).getTotalAmount()
        // );

        await time.increase(360000);
        await expect(await strategyManagercontract.connect(owner).harvest()).not
          .to.be.reverted;
        // console.log(
        //   "totalAmountAfterHarvest",
        //   await strategyManagercontract.connect(owner).getTotalPooledAmount()
        // );
        // console.log(
        //   "OwnerAmountAfterHarvest",
        //   await strategyManagercontract.connect(owner).balanceOf(owner.address)
        // );
        // console.log(
        //   "StrategyBalanceAfterHarvest",
        //   await posManagercontract.connect(owner).getTotalAmount()
        // );
        // console.log(
        //   "StrategyBalanceAfterHarvest1",
        //   await posManagercontract1.connect(owner).getTotalAmount()
        // );
      });
    });
  });
});
