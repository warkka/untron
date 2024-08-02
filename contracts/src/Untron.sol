// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISP1Verifier} from "@sp1-contracts/ISP1Verifier.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface ITronRelay {
    function latestBlock() external returns (uint32);
    function blockprint(uint32) external returns (bytes32);
}

interface ISender {
    function send(uint64, bytes memory) external;
}

contract Untron is Ownable {
    IERC20 constant usdt = IERC20(0x493257fD37EDB34451f62EDf8D2a0C418852bA4C); // bridged USDT @ zksync era

    constructor() Ownable(msg.sender) {}

    struct Params {
        ISP1Verifier verifier;
        ITronRelay relay;
        ISender sender;
        bytes32 vkey;
        uint64 mcyclesCost;
        uint64 fulfillerFee;
        address relayer;
        uint64 relayerFee;
        address paymaster;
    }

    Params public params;

    function setParams(Params calldata _params) external onlyOwner {
        params = _params;
    }

    bytes32 public stateHash = bytes32(0xe3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855); // sha256("")
    uint32 public latestKnownBlock;
    bytes32 public orderChain;
    bytes32 public latestKnownOrderChain;

    mapping(bytes32 => uint256) public orderIndex;
    mapping(address => Order) public orders; // tron address -> Order
    mapping(address => address) public tronAddresses; // tron address -> evm address
    mapping(address => Buyer) public buyers; // EVM address -> Buyer
    mapping(address => uint256) public orderCount; // tron address -> order count

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
        require(msg.sender == params.relayer || params.relayer == address(0));

        params.verifier.verifyProof(params.vkey, publicValues, proof);
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
        require(endBlock <= params.relay.latestBlock() - 19);
        require(endBlockprint == params.relay.blockprint(endBlock));
        require(orderIndex[startOrderChain] <= orderIndex[orderChain]);
        require(orderIndex[endOrderChain] > orderIndex[latestKnownOrderChain]);
        require(oldStateHash == stateHash);
        require(_mcyclesCost <= params.mcyclesCost);

        stateHash = newStateHash;
        latestKnownOrderChain = endOrderChain;

        require(sha256(abi.encode(closedOrders)) == closedOrdersHash);

        uint256 paymasterFine = 0;
        for (uint256 i = 0; i < closedOrders.orders.length; i++) {
            OrderState memory orderState = closedOrders.orders[i];
            Order memory order = orders[orderState.tronAddress];

            uint64 amount = orderState.inflow;
            uint64 costOverdraft = orderState.relayCost - amount;
            amount -= orderState.relayCost;
            amount -= order.relayerFee;
            amount = amount > order.amount ? order.amount : amount;
            uint64 surplus = order.amount - amount;

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

        // no "require"
        usdt.transferFrom(params.paymaster, address(this), paymasterFine);
        usdt.transfer(closedOrders.relayer, closedOrders.totalCost);
    }

    function jailbreak() external {
        require(params.relay.latestBlock() > latestKnownBlock + 300); // 15 minutes
        params.relayer = address(0);
    }
}
