// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

abstract contract UntronTools {
    function chainId() internal view returns (uint256 _chainId) {
        assembly {
            _chainId := chainid()
        }
    }
}
