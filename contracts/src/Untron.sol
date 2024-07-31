// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISP1Verifier} from "@sp1-contracts/ISP1Verifier.sol";

contract Untron {
    address public verifier;
    bytes32 public vkey;

    constructor(address _verifier, bytes32 _vkey) {
        verifier = _verifier;
        vkey = _vkey;
    }

    function verifyProof(bytes calldata proof, bytes calldata publicValues)
        public
        view
        returns (uint32, uint32, uint32)
    {
        ISP1Verifier(verifier).verifyProof(vkey, publicValues, proof);
        (uint32 n, uint32 a, uint32 b) = abi.decode(publicValues, (uint32, uint32, uint32));
        return (n, a, b);
    }
}
