// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@ultrasoundlabs/accounts/contracts/zksync/AccountsPaymaster.sol";
import "./interfaces/IUntronState.sol";

/// @title Module for storing Untron's variables
/// @author Ultrasound Labs
/// @notice This contract is used to store Untron's mutable state
/// @dev This contract only contains variables that may be changed by the UPGRADER_ROLE.
///      All other module-specific variables are stored in the respective modules.
abstract contract UntronState is IUntronState, AccessControlUpgradeable {
    /// @inheritdoc IUntronState
    bytes32 public constant override UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
}
