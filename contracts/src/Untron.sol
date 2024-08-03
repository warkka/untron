// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISP1Verifier} from "@sp1-contracts/ISP1Verifier.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface ITronRelay {
    function latestBlock() external returns (bytes32);
    function blockExists(bytes32) external returns (bool);
    function timestamp(bytes32) external returns (uint32);
}

interface ISender {
    function send(uint64, bytes memory) external;
}

contract Untron is Ownable {
    IERC20 constant usdt = IERC20(0x493257fD37EDB34451f62EDf8D2a0C418852bA4C); // bridged USDT @ zksync era

    constructor() Ownable(msg.sender) {}

    uint64 constant ORDER_TTL = 100; // 100 blocks = 5 min

    struct Params {
        ISP1Verifier verifier;
        ITronRelay relay;
        ISender sender;
        bytes32 vkey;
        uint64 feePerBlock;
        address relayer;
        address paymaster;
        uint64 revealerFee;
    }

    Params public params;

    function setParams(Params calldata _params) external onlyOwner {
        params = _params;
    }

    bytes32 public stateHash = bytes32(0xe3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855); // sha256("")
    bytes32 public latestKnownBlock;
    bytes32 public latestKnownOrder;

    bytes32 public latestOrder;
    uint256 public totalOrders;

    mapping(bytes32 => uint32) public orderCreation; // order chained hash -> tron block
    mapping(address => Order) public orders; // tron address -> Order
    mapping(address => address) public tronAddresses; // tron address -> evm address
    mapping(address => Buyer) public buyers; // EVM address -> Buyer
    mapping(address => uint256) public orderCount; // tron address -> order count

    struct Order {
        uint64 size;
        uint64 rate;
        ISender sender;
        bytes transferData;
        address fulfiller;
        uint64 fulfilledAmount;
        uint64 fulfillerFee;
    }

    struct Buyer {
        address _address;
        uint64 liquidity;
        uint64 order;
        uint64 minDeposit;
    }

    struct OrderState {
        address tronAddress;
        uint32 timestamp;
        uint64 inflow;
        uint64 minDeposit;
    }

    function revealDeposits(bytes calldata proof, bytes calldata publicValues, OrderState[] calldata closedOrders)
        external
    {
        require(msg.sender == params.relayer || params.relayer == address(0));

        params.verifier.verifyProof(params.vkey, publicValues, proof);
        (
            address relayer,
            bytes32 startBlock,
            bytes32 endBlock,
            bytes32 startOrder,
            bytes32 endOrder,
            bytes32 oldStateHash,
            bytes32 newStateHash,
            bytes32 closedOrdersHash,
            uint64 _feePerBlock,
            uint64 totalFee
        ) = abi.decode(
            publicValues, (address, bytes32, bytes32, bytes32, bytes32, bytes32, bytes32, bytes32, uint64, uint64)
        );

        require(msg.sender == relayer);
        require(startBlock == latestKnownBlock);
        require(params.relay.blockExists(endBlock));
        require(startOrder == latestKnownOrder);
        require(orderCreation[endOrder] > totalOrders);
        require(oldStateHash == stateHash);
        require(_feePerBlock == params.feePerBlock);

        stateHash = newStateHash;
        latestKnownOrder = endOrder;

        require(sha256(abi.encode(closedOrders)) == closedOrdersHash);

        uint64 paymasterFine = 0;
        for (uint256 i = 0; i < closedOrders.length; i++) {
            OrderState memory state = closedOrders[i];
            Order memory order = orders[state.tronAddress];

            uint64 amount = order.size < state.inflow ? order.size : state.inflow;
            amount = amount * 1e6 / order.rate;
            uint64 _paymasterFine = params.feePerBlock * ORDER_TTL - amount;
            amount -= params.feePerBlock * ORDER_TTL;
            amount -= params.revealerFee;
            uint64 left = order.size - amount;
            buyers[tronAddresses[state.tronAddress]].liquidity += left;

            paymasterFine += _paymasterFine;
            if (order.fulfilledAmount == amount) {
                require(usdt.transfer(order.fulfiller, amount));
            } else {
                order.sender.send(amount, order.transferData);
            }
        }
        totalFee += params.revealerFee * uint64(closedOrders.length);

        require(usdt.transfer(msg.sender, totalFee));
    }

    function blockIdToNumber(bytes32 blockId) internal pure returns (uint256) {
        return uint256(blockId) >> 192;
    }

    function jailbreak() external {
        require(blockIdToNumber(params.relay.latestBlock()) > blockIdToNumber(latestKnownBlock) + 600); // 30 minutes
        params.relayer = address(0);
    }
}
