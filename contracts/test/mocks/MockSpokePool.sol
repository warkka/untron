// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../../src/interfaces/external/V3SpokePoolInterface.sol";

contract MockSpokePool is V3SpokePoolInterface {
    event DepositV3Called(
        address depositor,
        address recipient,
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 destinationChainId,
        address exclusiveRelayer,
        uint32 quoteTimestamp,
        uint32 fillDeadline,
        uint32 exclusivityDeadline,
        bytes message
    );

    function depositV3(
        address depositor,
        address recipient,
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 destinationChainId,
        address exclusiveRelayer,
        uint32 quoteTimestamp,
        uint32 fillDeadline,
        uint32 exclusivityDeadline,
        bytes calldata message
    ) external payable {
        emit DepositV3Called(
            depositor,
            recipient,
            inputToken,
            outputToken,
            inputAmount,
            outputAmount,
            destinationChainId,
            exclusiveRelayer,
            quoteTimestamp,
            fillDeadline,
            exclusivityDeadline,
            message
        );
    }

    // Implement other functions as needed for testing
    function speedUpV3Deposit(address, uint32, uint256, address, bytes calldata, bytes calldata) external {}

    function fillV3Relay(V3RelayData calldata, uint256) external {}

    function fillV3RelayWithUpdatedDeposit(
        V3RelayData calldata,
        uint256,
        uint256,
        address,
        bytes calldata,
        bytes calldata
    ) external {}

    function requestV3SlowFill(V3RelayData calldata) external {}

    function executeV3SlowRelayLeaf(V3SlowFill calldata, uint32, bytes32[] calldata) external {}
}
