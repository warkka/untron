// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./IUntronTransfers.sol";

interface IUntronCore is IUntronTransfers {
    struct Order {
        address creator;
        uint256 size;
        uint256 rate;
        Transfer transfer;
    }

    struct Provider {
        uint256 liquidity;
        uint256 rate;
        uint256 minDeposit;
        address[] receivers;
    }

    struct Inflow {
        bytes32 order;
        uint256 inflow;
    }
}
