require("@nomicfoundation/hardhat-toolbox");
require("@nomicfoundation/hardhat-chai-matchers");
require("hardhat-gas-reporter");
require("dotenv").config();

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.8.20",
      },
    ],
  },
  // defaultNetwork: "optimism",
  networks: {
    hardhat: {
      forking: {
        url: process.env.RPC_link,
        blockNumber: 113610800,
      },
    },
    local: {
      url: "http://127.0.0.1:8545/",
    },
  },
  gasReporter: {
    enabled: false,
    gasPrice: 1,
    showTimeSpent: true,
    showMethodSig: true,
    onlyCalledMethods: false,
    currency: "USD",
    coinmarketcap: "d8f6f86a-4110-4191-ab5a-6b3708ca3504",
  },
};
