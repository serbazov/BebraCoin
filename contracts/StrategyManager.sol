//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./IPositionManager.sol";
import "./BebraCoin.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "hardhat/console.sol";

contract StrategyManager is Ownable, Bebra {
    IPositionManager[] strategies;
    mapping(address => uint256) private strategiesBalances;
    uint[] strategiesWeights;
    uint8 strategiesCount;
    address private constant USDC = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
    event StrategiesChanged(
        address[] newStrategiesAddresses,
        uint[] newStrategiesWeights
    );
    event Deposit(address depositor, uint amount);
    event Withdraw(address withdrawer, uint amount);
    event TokenRebased(
        uint256 indexed reportTimestamp,
        uint256 preTotalShares,
        uint256 preTotalPooledAmount,
        uint256 postTotalShares,
        uint256 postTotalPooledAmount
    );

    constructor() Ownable(msg.sender) {}

    function changeStrategies(
        address[] memory _strategiesBatch,
        uint[] memory _strategiesWeight
    ) external onlyOwner {
        require(
            _strategiesBatch.length == _strategiesWeight.length,
            "wrong input length"
        );
        delete strategies;
        delete strategiesWeights;
        uint8 _strategiesCount = uint8(_strategiesBatch.length);
        uint fullWeght;
        for (uint i = 0; i < _strategiesCount; i++) {
            fullWeght += _strategiesWeight[i];
        }
        require(fullWeght == 1e18, "wrong strategies weights");
        strategiesCount = _strategiesCount;
        console.log(_strategiesCount);
        for (uint i = 0; i < _strategiesCount; i++) {
            strategies.push(IPositionManager(_strategiesBatch[i]));
            strategiesWeights.push(_strategiesWeight[i]);
            IERC20(USDC).approve(_strategiesBatch[i], 2 ** 256 - 1);
        }
        emit StrategiesChanged(_strategiesBatch, _strategiesWeight);
    }

    function _getTotalPooledAmount() internal view override returns (uint256) {
        return (getTotalPooledAmount());
    }

    function getTotalPooledAmount() public view returns (uint amount) {
        for (uint i = 0; i < strategiesCount; i++) {
            amount += strategiesBalances[address(strategies[i])];
        }
        return amount;
    }

    function deposit(uint amount) external {
        require(
            IERC20(USDC).balanceOf(msg.sender) > amount,
            "your balance not enough"
        );
        require(strategiesCount > 0, "no strategies to deposit");
        SafeERC20.safeTransferFrom(
            IERC20(USDC),
            msg.sender,
            address(this),
            amount
        );
        console.log(IERC20(USDC).balanceOf(address(this)));
        (uint pooledAmount1, uint totalShares1) = _getDataForRebase();
        for (uint i = 0; i < strategiesCount; i++) {
            strategies[i].openPosition((amount * strategiesWeights[i]) / 1e18);
            strategiesBalances[address(strategies[i])] = strategies[i]
                .getTotalAmount();
        }
        _mintShares(msg.sender, amount);
        (uint pooledAmount2, uint totalShares2) = _getDataForRebase();
        emit TokenRebased(
            block.timestamp,
            totalShares1,
            pooledAmount1,
            totalShares2,
            pooledAmount2
        );
        emit Deposit(msg.sender, amount);
    }

    function _getDataForRebase()
        internal
        view
        returns (uint pooledAmount, uint totalShares)
    {
        return (getTotalPooledAmount(), _getTotalShares());
    }

    function closePosition(uint amount) external {
        _burnShares(msg.sender, amount);
        uint[] memory withdrawSharesPercentage = new uint[](strategiesCount);
        (uint pooledAmount1, uint totalShares1) = _getDataForRebase();
        for (uint i = 0; i < strategiesCount; i++) {
            withdrawSharesPercentage[i] =
                (amount * strategiesWeights[i]) /
                strategies[i].getTotalAmount();
            strategies[i].closePosition(
                (withdrawSharesPercentage[i] * strategiesWeights[i]) / 1e18
            );
            strategiesBalances[address(strategies[i])] = strategies[i]
                .getTotalAmount();
        }
        (uint pooledAmount2, uint totalShares2) = _getDataForRebase();
        emit TokenRebased(
            block.timestamp,
            totalShares1,
            pooledAmount1,
            totalShares2,
            pooledAmount2
        );
        emit Withdraw(msg.sender, amount);
    }

    function harvest() external {
        (uint pooledAmount1, uint totalShares1) = _getDataForRebase();
        for (uint i = 0; i < strategiesCount; i++) {
            strategies[i].claimAndReinvest();
            strategiesBalances[address(strategies[i])] = strategies[i]
                .getTotalAmount();
        }
        (uint pooledAmount2, uint totalShares2) = _getDataForRebase();
        emit TokenRebased(
            block.timestamp,
            totalShares1,
            pooledAmount1,
            totalShares2,
            pooledAmount2
        );
    }
}
