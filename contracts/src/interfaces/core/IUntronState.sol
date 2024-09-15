// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

/// @title Interface for UntronState contract
/// @author Ultrasound Labs
/// @notice This interface defines the functions and structs used in the UntronState contract.
interface IUntronState {
    /// @notice Role for upgrading Untron's state and contracts
    function UPGRADER_ROLE() external view returns (bytes32);
}
