// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ITronRelay {
    function latestBlockNumber() external returns (uint256);
    function blocks(uint256) external returns (bytes32);
}
