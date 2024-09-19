// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./core/UntronCore.sol";
import "./interfaces/IUntronV1.sol";

contract UntronV1 is Initializable, UntronCore, UUPSUpgradeable, IUntronV1 {
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
        bytes32 _vkey
    ) public initializer {
        __UUPSUpgradeable_init();
        __UntronCore_init(
            _blockId, _stateHash, _maxOrderSize, _spokePool, _usdt, _swapper, _relayerFee, _feePoint, _verifier, _vkey
        );
    }

    /// @inheritdoc IUntronV1
    function estimateCollateral(address, address, uint256 size, uint256 rate, Transfer memory)
        public
        view
        returns (uint256)
    {
        // the collateral is min(10 USDT, 1% of the amount)
        (uint256 amount,) = conversion(size, rate, 0, false);
        uint256 onePercent = amount / 100;
        return onePercent < 10e6 ? 10e6 : onePercent;
    }

    mapping(address => uint256) internal _collateral;

    /// @inheritdoc UntronCore
    function _whenReceiverIsFreed(address receiver, bool dueToExpiry) internal override {
        bytes32 orderId = _isReceiverBusy[receiver];
        address creator = _orders[orderId].creator;
        uint256 collateral = _collateral[creator];
        internalTransfer(dueToExpiry ? _orders[orderId].provider : creator, collateral);
    }

    /// @inheritdoc UntronCore
    function _canCreateOrder(address provider, address receiver, uint256 size, uint256 rate, Transfer memory transfer)
        internal
        override
        returns (bool result)
    {
        require(_collateral[msg.sender] == 0, "Order creator has a running order");

        uint256 collateral = estimateCollateral(provider, receiver, size, rate, transfer);
        internalTransferFrom(msg.sender, collateral);
        _collateral[msg.sender] = collateral;
        result = true;
    }

    /// @notice Authorizes the upgrade of the contract.
    /// @param newImplementation The address of the new implementation.
    /// @dev This is a UUPS-related function.
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}
}
