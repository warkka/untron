// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../../src/interfaces/core/external/IAggregationRouterV6.sol";

contract MockAggregationRouter is IAggregationRouterV6 {
    event SwapCalled(address executor, SwapDescription desc, bytes permit, bytes data);

    function swap(address executor, SwapDescription calldata desc, bytes calldata permit, bytes calldata data)
        external
        payable
        returns (uint256 returnAmount, uint256 spentAmount)
    {
        emit SwapCalled(executor, desc, permit, data);
        return (desc.minReturnAmount, desc.amount);
    }
}
