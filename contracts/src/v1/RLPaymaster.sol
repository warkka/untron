// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {Transaction} from "@matterlabs/zksync-contracts/contracts/system-contracts/interfaces/IPaymaster.sol";
import "../interfaces/v1/IRLPaymaster.sol";
import "./RateLimiting.sol";

/// @title Rate limited paymaster for ZKsync Era
/// @author Ultrasound Labs
/// @notice This paymaster allows to register users and limit their allowed fundings per time period.
contract RLPaymaster is RateLimiting, IRLPaymaster {
    mapping(address => bool) internal isFunded;

    function validateAndPayForPaymasterTransaction(bytes32, bytes32, Transaction calldata _transaction)
        external
        payable
        returns (bytes4, bytes memory)
    {
        // output magic. must be equal to PAYMASTER_VALIDATION_SUCCESS_MAGIC (selector of this function) to approve funding
        bytes4 magic;
        // context. we don't use it so it's empty
        bytes memory b = new bytes(0);

        // get sender and selectorof the tx
        address from = address(uint160(_transaction.from));
        bytes4 selector = bytes4(_transaction.data[:4]);

        // TODO: this might contain a vulnerability

        // approve funding if:
        if (
            // necessary delay has passed
            _hasDelayPassed(
                // for the function that is called
                selector,
                // for initiator of the tx
                from,
                // at paymaster's rate
                // TODO: Check if this is correct
                rate - 1,
                // at paymaster's timeframe
                per
            )
            // and transaction is done to this contract
            && address(uint160(_transaction.to)) == address(this)
        ) {
            // then set magic to PAYMASTER_VALIDATION_SUCCESS_MAGIC (approved)
            magic = PAYMASTER_VALIDATION_SUCCESS_MAGIC;
            _logCall(from, selector);
            isFunded[from] = true;
        }

        // return stuff
        return (magic, b);
    }

    function postTransaction(bytes calldata, Transaction calldata, bytes32, bytes32, ExecutionResult, uint256)
        external
        payable
    {}
}
