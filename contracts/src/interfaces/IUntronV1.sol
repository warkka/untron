// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./core/IUntronCore.sol";
import "./v1/IRLPaymaster.sol";

interface IUntronV1 is IUntronCore, IRLPaymaster {
    function UNLIMITED_CREATOR_ROLE() external pure returns (bytes32);
}
