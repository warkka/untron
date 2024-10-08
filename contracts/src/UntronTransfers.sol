// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./interfaces/external/V3SpokePoolInterface.sol";
import "./interfaces/external/IAggregationRouterV6.sol";
import "./interfaces/IUntronTransfers.sol";
import "./UntronTools.sol";

/// @title Extensive pausable transfer module for Untron
/// @author Ultrasound Labs
/// @notice This module is responsible for handling all the transfers in the Untron protocol.
/// @dev Transfer, within Untron terminology (unless specified otherwise: USDT transfer, Tron transfer, etc),
///      is the process of order creator receiving the coins in the L2 ecosystem for the USDT Tron they sent.
///      Natively, these tokens are USDT L2 (on ZKsync Era, Untron's host chain).
///      However, the module is designed to be as chain- and coin-agnostic as possible,
///      so it supports on-the-fly swaps of USDT L2 to other coins and cross-chain transfers through Across bridge.
///      Only this module must be used to manage the funds in the Untron protocol,
///      as it contains the pausing logic in case of emergency.
abstract contract UntronTransfers is
    IUntronTransfers,
    UntronTools,
    Initializable,
    PausableUpgradeable,
    OwnableUpgradeable
{
    /// @notice Initializes the contract with the provided parameters.
    /// @param _spokePool The address of the Across bridge's SpokePool contract.
    /// @param _usdt The address of the USDT token.
    /// @param _swapper The address of the contract implementing swap logic.
    ///                  In our case, it's 1inch V6 aggregation router.
    function __UntronTransfers_init(address _spokePool, address _usdt, address _swapper) internal onlyInitializing {
        _setTransfersVariables(_usdt, _spokePool, _swapper);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // UntronTransfers variables
    address public usdt;
    address public spokePool;
    address public swapper;

    function _setTransfersVariables(address _usdt, address _spokePool, address _swapper) internal {
        usdt = _usdt;
        spokePool = _spokePool;
        swapper = _swapper;
    }

    /// @inheritdoc IUntronTransfers
    function setTransfersVariables(address _usdt, address _spokePool, address _swapper) external override onlyOwner {
        _setTransfersVariables(_usdt, _spokePool, _swapper);
    }

    /// @notice Swaps USDT to the desired token specified in the transfer.
    /// @param transfer The transfer details.
    /// @param amount The amount of USDT to swap.
    /// @return output The amount of the desired token received.
    function swapUSDT(Transfer memory transfer, uint256 amount) internal returns (uint256 output) {
        // construct the swap description for 1inch
        IAggregationRouterV6.SwapDescription memory desc = IAggregationRouterV6.SwapDescription({
            // source (input) token is always USDT L2 (zksync)
            srcToken: IERC20(usdt),
            // destination (output) token is the one specified in the transfer
            // important note: we don't check if the token is supported by Across bridge,
            // as this must be done offchain.
            dstToken: IERC20(transfer.outToken),
            // we receive all the stuff in this contract
            // TODO: figure out why srcReceiver and dstReceiver are different fields
            srcReceiver: payable(address(this)),
            dstReceiver: payable(address(this)),
            // amount of USDT to swap
            amount: amount,
            // minimum amount of output token to receive
            minReturnAmount: transfer.minOutputPerUSDT * amount / 1e6,
            // we're not using flags
            flags: 0
        });

        // decode the swap data into executor address and data to perform the 1inch swap
        (address executor, bytes memory data) = abi.decode(transfer.swapData, (address, bytes));

        // perform the 1inch swap
        (output,) = IAggregationRouterV6(swapper).swap(
            executor,
            desc,
            "", // We're not using the permit functionality
            data // This should be obtained from the 1inch API
        );
    }

    /// @notice Performs the transfer.
    /// @param transfer The transfer details.
    /// @param amount The amount of USDT to transfer.
    function smartTransfer(Transfer memory transfer, uint256 amount) internal whenNotPaused {
        // if the transfer requires a swap, perform the swap
        if (transfer.doSwap) {
            // approve the swapper to spend the USDT.
            // we don't approve uint256.max in the constructor in case 1inch gets hacked.
            IERC20(usdt).approve(swapper, amount);
            // perform the swap (swapper address is used in swapUSDT)
            uint256 output = swapUSDT(transfer, amount);

            // if the transfer requires a fixed output amount,
            // we take the excessive amount and transfer it to the protocol owner
            if (transfer.fixedOutput) {
                amount = transfer.minOutputPerUSDT * amount / 1e6 + transfer.acrossFee;
                require(output >= amount, "Insufficient output amount");
                internalTransfer(usdt, owner(), output - amount);
            } else {
                // if the transfer doesn't require a fixed output amount,
                // the order creator will receive the entire output amount
                amount = output;
            }
        }

        // if we swapped, we send the swapped token, otherwise we send USDT
        address token = transfer.doSwap ? transfer.outToken : usdt;

        // if the transfer is within the same chain, perform an internal transfer
        if (transfer.chainId == chainId()) {
            internalTransfer(token, transfer.recipient, amount);
        } else {
            // otherwise, perform a cross-chain transfer through the Across bridge.
            // see https://docs.across.to/use-cases/instant-bridging-in-your-application/bridge-integration-guide for reference

            // approving the token to the spoke pool
            IERC20(token).approve(spokePool, amount);

            // deposit to the spoke pool
            V3SpokePoolInterface(spokePool).depositV3(
                msg.sender,
                transfer.recipient,
                token,
                address(0),
                amount,
                amount - transfer.acrossFee,
                transfer.chainId,
                address(0),
                uint32(block.timestamp - 36),
                uint32(block.timestamp + 1800),
                0,
                ""
            );
        }
    }

    /// @notice perform a native (onchain) ERC20 transfer
    /// @param token the token address
    /// @param to the recipient address
    /// @param amount the amount of USDT to transfer
    /// @dev transfers ERC20 token to "to" address.
    ///      needed for fulfiller/relayer-related operations and inside the smartTransfer function.
    function internalTransfer(address token, address to, uint256 amount) internal whenNotPaused {
        require(IERC20(token).transfer(to, amount));
    }

    /// @notice perform a native (USDT on ZKsync Era) ERC20 transferFrom
    /// @param from the sender address
    /// @param amount the amount of USDT to transfer
    /// @dev transfers USDT zksync from "from" to this contract.
    ///      needed for fulfiller/relayer-related operations and inside the smartTransfer function.
    function internalTransferFrom(address from, uint256 amount) internal whenNotPaused {
        require(IERC20(usdt).transferFrom(from, address(this), amount));
    }
}
