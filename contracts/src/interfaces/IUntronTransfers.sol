// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

interface IUntronTransfers {
    struct Transfer {
        address recipient;
        uint256 chainId;
        uint256 acrossFee;
        bool doSwap;
        address outToken;
        uint256 minOutputPerUSDT;
        bool fixedOutput;
        bytes swapData;
    }
}
