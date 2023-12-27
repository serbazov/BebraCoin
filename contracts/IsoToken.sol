//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IsoToken {
  function mint(uint mintAmount) external returns (uint);
  function redeem(uint redeemTokens) external returns (uint);
  function redeemUnderlying(uint redeemAmount) external returns (uint);
  function borrow(uint borrowAmount) external returns (uint);
  function repayBorrow(uint repayAmount) external returns (uint);
  function borrowBalanceCurrent(address account) external returns (uint);
  function balanceOf(address owner) external view returns (uint);
  function underlying() external view returns (address);
  function getAccountSnapshot(address account) external view returns (uint, uint, uint, uint);
}