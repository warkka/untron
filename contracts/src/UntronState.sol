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
abstract contract UntronState is Initializable, AccessControlUpgradeable, AccountsPaymaster, IUntronState {
    /// @inheritdoc IUntronState
    bytes32 public constant override UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    /// @notice Initializes the contract
    /// @dev This function is called once during the contract's deployment
    function __UntronState_init() internal onlyInitializing {
        // Initialize the paymaster with a rate limit of 10 gas sponsorships per 24 hours for one order creator.
        __AccountsPaymaster_init(msg.sender, 10, 24 hours, false);
        // Set the rate limit to 10 actions per 24 hours for one order creator, same as for the paymaster.
        // Both paymaster and normal rate limiting utilize "Accounts" library under the hood.
        _changeRateLimit(10, 24 hours);
    }

    // UntronCore variables
    bytes32 public blockId;
    bytes32 public actionChainTip;
    bytes32 public latestPerformedAction;
    bytes32 public stateHash;
    uint256 public maxOrderSize;

    /// @inheritdoc IUntronState
    function setUntronCoreVariables(
        bytes32 _blockId,
        bytes32 _actionChainTip,
        bytes32 _latestPerformedAction,
        bytes32 _stateHash,
        uint256 _maxOrderSize
    ) external onlyRole(UPGRADER_ROLE) {
        blockId = _blockId;
        actionChainTip = _actionChainTip;
        latestPerformedAction = _latestPerformedAction;
        stateHash = _stateHash;
        maxOrderSize = _maxOrderSize;
    }

    // UntronZK variables
    address public verifier;
    bytes32 public vkey;

    /// @inheritdoc IUntronState
    function setUntronZKVariables(address _verifier, bytes32 _vkey) external override onlyRole(UPGRADER_ROLE) {
        verifier = _verifier;
        vkey = _vkey;
    }

    // UntronFees variables
    uint256 public relayerFee; // percents
    uint256 public feePoint; // approx fee per ERC20 transfer in USD

    /// @inheritdoc IUntronState
    function setUntronFeesVariables(uint256 _relayerFee, uint256 _feePoint) external override onlyRole(UPGRADER_ROLE) {
        relayerFee = _relayerFee;
        feePoint = _feePoint;
    }

    // UntronTransfers variables
    address public usdt;
    address public spokePool;
    address public swapper;

    /// @inheritdoc IUntronState
    function setUntronTransfersVariables(address _usdt, address _spokePool, address _swapper)
        external
        override
        onlyRole(UPGRADER_ROLE)
    {
        usdt = _usdt;
        spokePool = _spokePool;
        swapper = _swapper;
    }

    // Accounts variables
    uint256 public maxSponsorships;
    uint256 public per;

    /// @notice Changes the rate and period of rate-limited calls with no checks
    /// @param _rate The rate of rate-limited calls
    /// @param _per The period of rate-limited calls
    /// @dev This function is only used during initialization and in changeRateLimit
    function _changeRateLimit(uint256 _rate, uint256 _per) internal {
        maxSponsorships = _rate;
        per = _per;
        // see natspec of this function in AccountsPaymaster
        setPaymasterConfig(_rate, _per, true);
    }

    /// @inheritdoc IUntronState
    function changeRateLimit(uint256 _rate, uint256 _per) external override onlyRole(UPGRADER_ROLE) {
        _changeRateLimit(_rate, _per);
    }
}
