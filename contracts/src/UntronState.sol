// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@ultrasoundlabs/accounts/contracts/zksync/AccountsPaymaster.sol";

abstract contract UntronState is Initializable, AccessControlUpgradeable, AccountsPaymaster {
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    function __UntronState_init() internal onlyInitializing {
        __AccountsPaymaster_init(msg.sender, 10, 24 hours, false);
        _changeRateLimit(10, 24 hours);
    }

    // UntronCore variables

    bytes32 internal blockId;
    bytes32 internal latestOrder;
    bytes32 internal latestClosedOrder;
    bytes32 internal stateHash;

    // UntronZK variables

    address internal verifier;
    bytes32 internal vkey;

    // UntronFees variables

    uint256 public relayerFee; // percents
    uint256 internal feePoint; // approx fee per ERC20 transfer in $

    // UntronTransfers variables

    address internal usdt;
    address internal spokePool;
    address internal swapper;

    // Accounts variables

    uint256 internal rate;
    uint256 internal per;

    function _changeRateLimit(uint256 _rate, uint256 _per) internal {
        rate = _rate;
        per = _per;
        setPaymasterConfig(_rate, _per, true);
    }

    function changeRateLimit(uint256 _rate, uint256 _per) external onlyRole(UPGRADER_ROLE) {
        _changeRateLimit(_rate, _per);
    }
}
