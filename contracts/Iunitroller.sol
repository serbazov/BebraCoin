//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./CToken.sol";

interface Iunitroller {
  function claimComp(address holder, CToken[] memory cTokens) external;
}