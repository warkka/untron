// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ISender {
    function send(uint64 amount, bytes calldata transferData) external;
}
