// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

/// @title Interface for UntronZK contract
/// @author Ultrasound Labs
/// @notice This interface defines the functions and structs used in the UntronZK contract.
interface IUntronZK {
    /// @notice Updates the UntronZK-related variables
    /// @param _verifier The new address of the ZK proof verifier contract
    /// @param _vkey The new verification key of the ZK program
    function setZKVariables(address _verifier, bytes32 _vkey) external;
}
