// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ISP1Verifier} from "@sp1-contracts/ISP1Verifier.sol";
import "./UntronState.sol";

abstract contract UntronZK is Initializable, UntronState {
    function __UntronZK_init() internal onlyInitializing {
        __UntronState_init();
    }

    function verifyProof(bytes memory proof, bytes memory publicValues) internal view {
        ISP1Verifier(verifier).verifyProof(vkey, publicValues, proof);
    }
}
