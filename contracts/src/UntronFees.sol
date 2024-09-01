// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./UntronState.sol";
import "./UntronTools.sol";

abstract contract UntronFees is UntronTools, Initializable, UntronState {
    uint256 constant bp = 1000000; // min 0.000001 i.e 0.0001%. made for consistency with usdt decimals

    function __UntronFees_init(uint256 _relayerFee, uint256 _feePoint) internal onlyInitializing {
        __UntronState_init();

        relayerFee = _relayerFee;
        feePoint = _feePoint;
    }

    function calculateFee(bool doSwap, uint256 _chainId) internal view returns (uint256 fee) {
        // I HATE ZKSYNC GAS SYSTEM

        if (doSwap) {
            fee += feePoint * 3; // swap is approx 3x more expensive than erc20 transfer
        }
        if (_chainId == chainId()) {
            fee += feePoint;
        } else {
            fee += feePoint * 2; // across deposit is approx 2x more expensive than erc20 transfer
        }
        fee += feePoint; // untron-specific activities cost about the same as erc20 transfer
    }

    function conversion(uint256 size, uint256 rate, uint256 fixedFee)
        internal
        view
        returns (uint256 value, uint256 fee)
    {
        uint256 out = (size * rate / bp);
        value = out * (bp - relayerFee) / bp;
        fee = value - out;
        value -= fixedFee;
    }
}
