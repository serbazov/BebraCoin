//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
pragma abicoder v2;

interface IPositionManager {
    function closePosition(uint sharesPercentage) external;

    function openPosition(uint initialAmount) external;

    function getTotalAmount() external view returns (uint totalAmount);

    function claimAndReinvest() external returns (uint balanceChange);
}
