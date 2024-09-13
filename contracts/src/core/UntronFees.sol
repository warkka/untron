// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./interfaces/IUntronFees.sol";
import "./UntronState.sol";
import "./UntronTools.sol";

/// @title Module for calculating fees in Untron protocol.
/// @author Ultrasound Labs
/// @notice This contract implements logic for calculating over fees and rates in Untron protocol.
abstract contract UntronFees is IUntronFees, UntronTools, Initializable, UntronState {
    /// @notice The number of basis points in 100%.
    uint256 constant bp = 1000000; // min 0.000001 i.e 0.0001%. made for consistency with usdt decimals
    /// @notice Initializes the contract with the provided parameters.
    /// @param _relayerFee The fee charged by the relayer, in percents.
    /// @param _feePoint The basic fee point used to calculate the fee per transfer.

    function __UntronFees_init(uint256 _relayerFee, uint256 _feePoint) internal onlyInitializing {
        _setFeesVariables(_relayerFee, _feePoint);
    }

    // UntronFees variables
    uint256 public relayerFee; // percents
    uint256 public feePoint; // approx fee per ERC20 transfer in USD

    function _setFeesVariables(uint256 _relayerFee, uint256 _feePoint) internal {
        relayerFee = _relayerFee;
        feePoint = _feePoint;
    }

    /// @inheritdoc IUntronFees
    function setFeesVariables(uint256 _relayerFee, uint256 _feePoint) external override onlyRole(UPGRADER_ROLE) {
        _setFeesVariables(_relayerFee, _feePoint);
    }

    /// @notice Calculates the fee for the transfer.
    /// @param doSwap Whether the transfer is a swap.
    /// @param _chainId The ID of the chain where the transfer is made.
    /// @return fee The fee for the transfer.
    function calculateFee(bool doSwap, uint256 _chainId) internal view returns (uint256 fee) {
        // I HATE ZKSYNC GAS SYSTEM

        if (doSwap) {
            fee += feePoint * 3; // swap is approx 3x more expensive than erc20 transfer
        }
        if (_chainId == chainId()) {
            fee += feePoint;
        } else {
            fee += feePoint * 2; // across deposit is approx 2x more expensive than erc20 transfer
        }
        fee += feePoint; // untron-specific activities cost about the same as erc20 transfer
    }

    /// @notice Converts USDT Tron (size) to USDT L2 (value) based on the rate, fixed fee, and relayer fee.
    /// @param size The size of the transfer in USDT Tron.
    /// @param rate The rate of the order.
    /// @param fixedFee The fixed fee for the transfer (normally taken by the fulfiller).
    /// @param includeRelayerFee Whether to include the relayer fee in the conversion.
    /// @return value The value of the transfer in USDT L2.
    /// @return fee The fee for the transfer in USDT L2.
    function conversion(uint256 size, uint256 rate, uint256 fixedFee, bool includeRelayerFee)
        internal
        view
        returns (uint256 value, uint256 fee)
    {
        // convert size into USDT L2 based on the rate
        uint256 out = (size * rate / bp);
        // if the relayer fee is included, subtract it from the converted size
        if (includeRelayerFee) {
            // subtract relayer fee from the converted size
            value = out * (bp - relayerFee) / bp;
            // and write the fee to the fee variable
            fee = out - value;
        } else {
            // if the relayer fee is not included, the value is just converted size (size * rate)
            value = out;
        }
        // subtract fixed fee from the output value
        value -= fixedFee;
    }
}
