// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library Tronlib {
    // tron uses god knows what format for timestamping
    // and this formula is an approximation.
    // i only figured out that it's in 1/100th of second
    // because timestamps in blocks differ by 300.
    // CALCULATION FOR THE SUBTRAHEND:
    // blockheader(62913164).raw_data.timestamp - (tronscan(62913164).timestamp * 100)
    function unixToTron(uint256 _timestamp) internal pure returns (uint32) {
        return uint32(_timestamp * 100 - 170539755000);
    }

    function blockIdToNumber(bytes32 blockId) internal pure returns (uint256) {
        return uint256(blockId) >> 192;
    }

    function getBlockId(bytes32 blockHash, uint256 blockNumber) internal pure returns (bytes32) {
        return bytes32((blockNumber << 192) | uint256(uint160(uint256(blockHash))));
    }
}
