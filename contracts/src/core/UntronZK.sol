// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ISP1Verifier} from "@sp1-contracts/ISP1Verifier.sol";
import "../interfaces/core/IUntronZK.sol";
import "./UntronState.sol";

/// @title Module for ZK-related logic in Untron
/// @author Ultrasound Labs
/// @notice This contract wraps ZK proof verification in a UUPS-compatible manner.
abstract contract UntronZK is IUntronZK, Initializable, UntronState {
    /// @notice Initializes the contract.
    /// @dev Under the hood, it just calls setZKVariables.
    function __UntronZK_init(address _verifier, bytes32 _vkey) internal onlyInitializing {
        _setZKVariables(_verifier, _vkey);
    }

    // UntronZK variables
    address public verifier;
    bytes32 public vkey;

    function _setZKVariables(address _verifier, bytes32 _vkey) internal {
        verifier = _verifier;
        vkey = _vkey;
    }

    /// @inheritdoc IUntronZK
    function setZKVariables(address _verifier, bytes32 _vkey) external override onlyRole(UPGRADER_ROLE) {
        _setZKVariables(_verifier, _vkey);
    }

    /// @notice verify the ZK proof
    /// @param proof The ZK proof to verify.
    /// @param publicValues The public values to verify the proof with.
    /// @dev reverts in case the proof is invalid. Currently wraps SP1 zkVM.
    function verifyProof(bytes memory proof, bytes memory publicValues) internal view {
        ISP1Verifier(verifier).verifyProof(vkey, publicValues, proof);
    }
}
