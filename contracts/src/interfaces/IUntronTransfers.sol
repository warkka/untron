// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

/// @title Interface for UntronTransfers
/// @author Ultrasound Labs
/// @notice This interface defines the functions and events related to Untron transfers.
interface IUntronTransfers {
    /// @notice Struct representing a transfer.
    struct Transfer {
        // recipient of the transfer
        address recipient;
        // destination chain ID of the transfer.
        // if not equal to the contract's chain ID, Across bridge will be used.
        uint256 chainId;
        // Across bridge fee. 0 in case of direct transfer.
        uint256 acrossFee;
        // whether to swap USDT to another token before sending to the recipient.
        bool doSwap;
        // address of the token to swap USDT to.
        address outToken;
        // minimum amount of output tokens to receive per 1 USDT L2.
        uint256 minOutputPerUSDT;
        // whether the minimum amount of output tokens is fixed.
        // if true, the order creator will receive exactly minOutputPerUSDT * amount of output tokens.
        // if false, the order creator will receive at least minOutputPerUSDT * amount of output tokens.
        bool fixedOutput;
        // data for the swap. Not used if doSwap is false.
        bytes swapData;
    }

    /// @notice Updates the UntronTransfers-related variables
    /// @param _usdt The new address of the USDT token
    /// @param _spokePool The new address of the SpokePool contract
    /// @param _swapper The new address of the swapper contract
    function setTransfersVariables(address _usdt, address _spokePool, address _swapper) external;
}
