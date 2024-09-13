// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@ultrasoundlabs/accounts/contracts/zksync/AccountsPaymaster.sol";
import "./core/UntronCore.sol";

contract UntronV1 is Initializable, AccountsPaymaster, UntronCore, UUPSUpgradeable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _spokePool,
        address _usdt,
        address _swapper,
        uint256 _relayerFee,
        uint256 _feePoint,
        address _verifier,
        bytes32 _vkey,
        uint256 _rate,
        uint256 _per
    ) public initializer {
        __UUPSUpgradeable_init();
        __UntronCore_init(_spokePool, _usdt, _swapper, _relayerFee, _feePoint, _verifier, _vkey);
        _changeRate(_rate, _per);
    }

    /// @notice Access Control role for unlimited order creation.
    /// @dev This role will be delegated to Untron team for integrations with projects not on ZKsync Era
    ///      so they could create orders on behalf of the protocol without creating accounts on Era.
    ///      We expect this design to be temporary and to be replaced with a more flexible and secure
    ///      design in the future.
    bytes32 public constant UNLIMITED_CREATOR_ROLE = keccak256("UNLIMITED_CREATOR_ROLE");

    uint256 public rate;
    uint256 public per;

    function _changeRate(uint256 _rate, uint256 _per) internal {
        rate = _rate;
        per = _per;
        setPaymasterConfig(_rate, _per, false);
    }

    function changeRate(uint256 _rate, uint256 _per) external onlyRole(UPGRADER_ROLE) {
        _changeRate(_rate, _per);
    }

    function _canCreateOrder(address, address, uint256, uint256, Transfer memory)
        internal
        override
        returns (bool result)
    {
        // TODO: it's messy and i think we should obsolete/rework AccountsPaymaster logic
        result = hasRole(UNLIMITED_CREATOR_ROLE, msg.sender) || _hasDelayPassed(msg.sender, per, rate, bytes4(0));
        _logCall(bytes4(0), msg.sender);
    }

    /// @notice Authorizes the upgrade of the contract.
    /// @param newImplementation The address of the new implementation.
    /// @dev This is a UUPS-related function.
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}
}
