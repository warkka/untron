// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

/// @title Interface for UntronState contract
/// @author Ultrasound Labs
/// @notice This interface defines the functions and structs used in the UntronState contract.
interface IUntronState {
    /// @notice Role for upgrading Untron's state and contracts
    function UPGRADER_ROLE() external view returns (bytes32);

    /// @notice Updates the UntronCore-related variables
    /// @param _blockId The new block ID of the latest known Tron block
    /// @param _latestOrder The new ID of the latest created order
    /// @param _latestClosedOrder The new ID of the latest closed order
    /// @param _stateHash The new hash of the latest state of Untron ZK program
    function setUntronCoreVariables(
        bytes32 _blockId,
        bytes32 _latestOrder,
        bytes32 _latestClosedOrder,
        bytes32 _stateHash
    ) external;

    /// @notice Updates the UntronZK-related variables
    /// @param _verifier The new address of the ZK proof verifier contract
    /// @param _vkey The new verification key of the ZK program
    function setUntronZKVariables(address _verifier, bytes32 _vkey) external;

    /// @notice Updates the UntronFees-related variables
    /// @param _relayerFee The new fee charged by the relayer (in percents)
    /// @param _feePoint The new basic fee used to calculate the fee per transfer
    function setUntronFeesVariables(uint256 _relayerFee, uint256 _feePoint) external;

    /// @notice The fee charged by the relayer
    function relayerFee() external view returns (uint256);

    /// @notice Updates the UntronTransfers-related variables
    /// @param _usdt The new address of the USDT token on ZKsync Era
    /// @param _spokePool The new address of the Across SpokePool contract
    /// @param _swapper The new address of the swap contract (1inch V6 aggregation pool)
    function setUntronTransfersVariables(address _usdt, address _spokePool, address _swapper) external;

    /// @notice Changes the rate and period of rate-limited calls
    /// @param _rate The rate of rate-limited calls
    /// @param _per The period of rate-limited calls
    function changeRateLimit(uint256 _rate, uint256 _per) external;
}
