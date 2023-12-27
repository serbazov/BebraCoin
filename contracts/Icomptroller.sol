//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import "./IsoToken.sol";

interface Icomptroller {
    function enterMarkets(
        address[] calldata cTokens
    ) external returns (uint[] memory);

    function checkMembership(
        address account,
        IsoToken cToken
    ) external view returns (bool);
}
