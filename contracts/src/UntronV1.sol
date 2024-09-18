// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./core/UntronCore.sol";
import "./v1/RLPaymaster.sol";
import "./interfaces/IUntronV1.sol";

contract UntronV1 is Initializable, UntronCore, UUPSUpgradeable, RLPaymaster, IUntronV1 {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        bytes32 _blockId,
        bytes32 _stateHash,
        uint256 _maxOrderSize,
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
        __UntronCore_init(
            _blockId, _stateHash, _maxOrderSize, _spokePool, _usdt, _swapper, _relayerFee, _feePoint, _verifier, _vkey
        );
        _changeRateLimit(_rate, _per);
    }

    /// @notice Access Control role for unlimited order creation.
    /// @dev This role will be delegated to Untron team for integrations with projects not on ZKsync Era
    ///      so they could create orders on behalf of the protocol without creating accounts on Era.
    ///      We expect this design to be temporary and to be replaced with a more flexible and secure
    ///      design in the future.
    bytes32 public constant UNLIMITED_CREATOR_ROLE = keccak256("UNLIMITED_CREATOR_ROLE");

    /// @inheritdoc UntronCore
    function _canCreateOrder(address provider, address, uint256 size, uint256, Transfer memory)
        internal
        override
        returns (bool result)
    {
        (uint256 amount,) = conversion(size, _providers[provider].rate, 0, false);

        // if the amount is equal to provider's liquidity, then the order creator must have UNLIMITED_CREATOR_ROLE,
        // because execution of reversed orders is trusted in Untron V1 implementation. We'll make it trustless
        // and collateral-based in the next versions of Untron.
        // otherwise, the order creator must either not exceed their rate limit or have the UNLIMITED_CREATOR_ROLE.
        if (hasRole(UNLIMITED_CREATOR_ROLE, msg.sender)) {
            result = true;
        } else if ((amount != _providers[provider].liquidity) || _hasDelayPassed(_selector(), msg.sender, rate, per)) {
            // isFunded is a flag set in the paymaster. If the paymaster is used, the flag is set to true.
            // This is so that we don't trigger _logCall twice, as it's also triggered in the paymaster.
            if (!isFunded[msg.sender]) {
                _logCall(msg.sender, _selector());
            } else {
                isFunded[msg.sender] = false;
            }
            result = true;
        }
    }

    /// @notice Authorizes the upgrade of the contract.
    /// @param newImplementation The address of the new implementation.
    /// @dev This is a UUPS-related function.
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}
}
