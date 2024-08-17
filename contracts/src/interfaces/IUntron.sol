// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./ITronRelay.sol";
import "./ISender.sol";
import {ISP1Verifier} from "@sp1-contracts/ISP1Verifier.sol";

interface IUntron {
    struct Params {
        ISP1Verifier verifier;
        ITronRelay relay;
        ISender sender;
        bytes32 vkey;
        address relayer;
        address registrar;
        uint64 minSize;
        uint64 feePerBlock;
        uint64 revealerFee;
        uint64 fulfillerFee;
        uint256 rateLimit;
        uint256 limitPer;
    }

    struct Order {
        address by;
        uint64 size;
        uint64 rate;
        bytes transferData;
        address fulfiller;
        uint64 fulfilledAmount;
    }

    struct Buyer {
        bool active;
        uint64 liquidity;
        uint64 rate;
        uint64 minDeposit;
    }

    struct ClosedOrder {
        address tronAddress;
        uint32 timestamp;
        uint64 inflow;
        uint64 minDeposit;
    }

    function params() external view returns (Params memory);
    function params(Params calldata __params) external;
    function stateHash() external view returns (bytes32);
    function latestKnownBlock() external view returns (bytes32);
    function latestKnownOrder() external view returns (bytes32);
    function latestOrder() external view returns (bytes32);
    function totalOrders() external view returns (uint256);
    function orderTimestamps(uint256 index) external view returns (uint256);
    function orderIndexes(bytes32 order) external view returns (uint256);
    function activeOrders(address tronAddress) external view returns (Order memory);
    function evmAddresses(address tronAddress) external view returns (address);
    function buyers(address evmAddress) external view returns (Buyer memory);
    function orderCount(address tronAddress) external view returns (uint256);
    function setBuyer(uint64 liquidity, uint64 rate, uint64 minDeposit) external;
    function closeBuyer() external;
    function canCreateOrder(address who) external view returns (bool);
    function register(bytes calldata registrarSig) external;
    function createOrder(address tronAddress, uint64 size, bytes calldata transferData) external;
    function fulfill(address[] calldata _tronAddresses, uint64[] calldata amounts) external;
    function revealDeposits(bytes calldata proof, bytes calldata publicValues, ClosedOrder[] calldata closedOrders)
        external;
    function jailbreak() external;
}
