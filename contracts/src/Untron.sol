// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISP1Verifier} from "@sp1-contracts/ISP1Verifier.sol";

interface ITronRelay {
    function latestBlock() external returns (uint32);
    function blockprint(uint32) external returns (bytes32);
}

interface ISender {
    function send(uint64, bytes memory) external;
}

contract Untron {
    ISP1Verifier public verifier;
    ITronRelay public relay;
    ISender public sender;
    IERC20 public usdt;
    bytes32 public vkey;

    constructor(ISP1Verifier _verifier, ITronRelay _relay, ISender _sender, bytes32 _vkey) {
        verifier = _verifier;
        relay = _relay;
        sender = _sender;
        vkey = _vkey;
    }

    bytes32 public stateHash = bytes32(0xe3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855); // sha256("")
    uint64 public mcyclesCost;
    uint64 fulfillerFee;
    uint64 relayerFee;

    uint32 public latestKnownBlock;
    bytes32 orderChain;
    bytes32 latestKnownOrder;

    mapping(bytes32 => uint256) public orderIndex;
    mapping(bytes32 => bool) public pastState;
    mapping(address => Order) public orders; // tron address -> Order
    mapping(address => address) public tronAddresses; // tron address -> evm address
    mapping(address => Buyer) public buyers; // evm address -> Buyer

    struct Order {
        uint32 timestamp;
        ISender sender;
        uint64 amount;
        bytes transferData;
        address fulfiller;
        uint64 fulfilledAmount;
        uint64 relayerFee;
    }

    struct Buyer {
        address _address;
        uint64 liquidity;
        uint64 order;
        uint64 minOrderSize;
    }

    struct RelayerCost {
        address relayer;
        uint64 cost;
    }

    struct State {
        address relayer;
        uint64 totalCost;
        OrderState[] orders;
    }

    struct OrderState {
        address tronAddress;
        uint32 timestamp;
        uint64 inflow;
        uint64 relayCost;
    }

    function revealDeposits(bytes calldata proof, bytes calldata publicValues, State calldata closedOrders) external {
        verifier.verifyProof(vkey, publicValues, proof);
        (
            uint32 startBlock,
            uint32 endBlock,
            bytes32 endBlockprint,
            bytes32 startOrderChain,
            bytes32 endOrderChain,
            bytes32 oldStateHash,
            bytes32 newStateHash,
            bytes32 closedOrdersHash,
            uint64 _mcyclesCost
        ) = abi.decode(publicValues, (uint32, uint32, bytes32, bytes32, bytes32, bytes32, bytes32, bytes32, uint64));

        require(startBlock <= latestKnownBlock);
        require(endBlock <= relay.latestBlock() - 19);
        require(endBlockprint == relay.blockprint(endBlock));
        require(orderIndex[startOrderChain] <= orderIndex[orderChain]);
        require(orderIndex[endOrderChain] > orderIndex[latestKnownOrder]);
        require(pastState[oldStateHash]);
        require(_mcyclesCost <= mcyclesCost);

        stateHash = newStateHash;
        pastState[newStateHash] = true;

        require(sha256(abi.encode(closedOrders)) == closedOrdersHash);

        uint256 paymasterFine = 0;
        for (uint256 i = 0; i < closedOrders.orders.length; i++) {
            OrderState memory orderState = closedOrders.orders[i];
            Order memory order = orders[orderState.tronAddress];

            uint256 amount = orderState.inflow;
            uint256 costOverdraft = orderState.relayCost - amount;
            amount -= orderState.relayCost;
            amount -= order.relayerFee;
            amount = amount > order.amount ? order.amount : amount;
            uint256 surplus = order.amount - amount;

            if (costOverdraft != 0) {
                paymasterFine += costOverdraft;
            } else if (order.fulfilledAmount == amount) {
                require(usdt.transfer(order.fulfiller, amount));
            } else {
                order.sender.send(amount, order.transferData);
            }

            buyers[tronAddresses[orderState.tronAddress]].liquidity += surplus;
            delete orders[orderState.tronAddress];
        }
    }
}
