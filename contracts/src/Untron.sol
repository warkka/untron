// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISP1Verifier} from "@sp1-contracts/ISP1Verifier.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./interfaces/ITronRelay.sol";
import "./interfaces/ISender.sol";
import "./Tronlib.sol";

contract Untron is Ownable {
    IERC20 constant usdt = IERC20(0x493257fD37EDB34451f62EDf8D2a0C418852bA4C); // bridged USDT @ zksync era

    constructor() Ownable(msg.sender) {}

    uint64 constant ORDER_TTL = 100; // 100 blocks = 5 min

    struct Params {
        ISP1Verifier verifier;
        ITronRelay relay;
        ISender sender;
        bytes32 vkey;
        address relayer;
        address paymaster;
        uint64 minSize;
        uint64 feePerBlock;
        uint64 revealerFee;
        uint64 fulfillerFee;
        uint256 rateLimit;
        uint256 limitPer;
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

    uint256[] public orderTimestamps; // order index -> timestamp
    mapping(bytes32 => uint256) public orderIndexes;
    mapping(address => Order) public activeOrders; // tron address -> Order
    mapping(address => address) public evmAddresses; // tron address -> evm address
    mapping(address => Buyer) public buyers; // EVM address -> Buyer
    mapping(address => uint256) public orderCount; // tron address -> order count

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
        uint64 minDeposit; // needed for reverse swaps
    }

    struct OrderChain {
        bytes32 prev;
        uint32 timestamp;
        address tronAddress;
        uint64 minDeposit;
    }

    function setBuyer(uint64 liquidity, uint64 rate, uint64 minDeposit) external {
        require(usdt.transferFrom(msg.sender, address(this), liquidity));

        buyers[msg.sender].active = true;
        buyers[msg.sender].liquidity += liquidity;
        buyers[msg.sender].rate = rate;
        buyers[msg.sender].minDeposit = minDeposit;
    }

    function closeBuyer() external {
        require(usdt.transfer(msg.sender, buyers[msg.sender].liquidity));

        delete buyers[msg.sender];
    }

    mapping(address => uint256[]) userActions; // address -> timestamps of actions
    // checks whether the user can
    // create an order. when they can't, it must be false,
    // and vice versa. by default, all users can't
    // unless they register and this is set to true.
    // this is made like this to save storage slots.
    mapping(address => bool) internal _canCreateOrder;

    function canCreateOrder(address who) internal view returns (bool) {
        return _canCreateOrder[who];
    }

    function register(bytes calldata paymasterSig) external {
        require(ECDSA.recover(bytes32(uint256(uint160(msg.sender))), paymasterSig) == params.paymaster);
        require(userActions[msg.sender].length == 0);
        _canCreateOrder[msg.sender] = true;
    }

    function createOrder(address tronAddress, uint64 size, bytes calldata transferData) external {
        require(canCreateOrder(msg.sender), "bs");
        require(
            userActions[msg.sender][userActions[msg.sender].length - params.rateLimit] + params.limitPer
                < block.timestamp,
            "rl"
        );
        require(size >= params.minSize);
        require(activeOrders[tronAddress].size == 0);

        address buyer = evmAddresses[tronAddress];
        require(buyers[buyer].active);
        require(buyers[buyer].liquidity >= size);
        buyers[buyer].liquidity -= size;

        activeOrders[tronAddress] = Order({
            by: msg.sender,
            size: size,
            rate: buyers[buyer].rate,
            transferData: transferData,
            fulfiller: address(0),
            fulfilledAmount: 0
        });

        uint32 orderTimestamp = Tronlib.unixToTron(block.timestamp);
        latestOrder = sha256(
            abi.encode(
                OrderChain({
                    prev: latestOrder,
                    timestamp: orderTimestamp,
                    tronAddress: tronAddress,
                    minDeposit: buyers[buyer].minDeposit
                })
            )
        );
        totalOrders++;

        userActions[msg.sender].push(block.timestamp);
        orderIndexes[latestOrder] = orderTimestamps.length;
        orderTimestamps.push(orderTimestamp);
        _canCreateOrder[msg.sender] = false;
    }

    function fulfill(address[] calldata _tronAddresses, uint64[] calldata amounts) external {
        for (uint256 i = 0; i < _tronAddresses.length; i++) {
            address tronAddress = _tronAddresses[i];

            if (activeOrders[tronAddress].fulfilledAmount != 0) {
                continue; // not require bc someone could fulfill ahead of them
            }

            // TODO: Should we verify that the amount fulfills the order entirely (minus the fee)?
            //       If there is a partial fullfillment then when revealing the user would be getting
            //       the partial fulfillment + the total of the order
            uint64 amount = amounts[i];
            require(usdt.transferFrom(msg.sender, address(this), amount));

            params.sender.send(amount, activeOrders[tronAddress].transferData);
            activeOrders[tronAddress].fulfiller = msg.sender;
            activeOrders[tronAddress].fulfilledAmount = amount;
        }
    }

    function _isLastAtTimestamp(bytes32 order, uint32 timestamp) internal view returns (bool) {
        uint256 orderIndex = orderIndexes[order];
        if (orderTimestamps[orderIndex] <= timestamp && orderTimestamps[orderIndex + 1] > timestamp) {
            return true;
        }
        return false;
    }

    function revealDeposits(bytes calldata proof, bytes calldata publicValues, ClosedOrder[] calldata closedOrders)
        external
    {
        require(msg.sender == params.relayer || params.relayer == address(0));

        params.verifier.verifyProof(params.vkey, publicValues, proof);
        (
            address relayer,
            bytes32 startBlock,
            bytes32 endBlock,
            uint32 endBlockTimestamp,
            bytes32 startOrder,
            bytes32 endOrder,
            bytes32 oldStateHash,
            bytes32 newStateHash,
            bytes32 closedOrdersHash,
            uint64 _feePerBlock,
            uint64 totalFee
        ) = abi.decode(
            publicValues,
            (address, bytes32, bytes32, uint32, bytes32, bytes32, bytes32, bytes32, bytes32, uint64, uint64)
        );

        require(msg.sender == relayer);
        require(startBlock == latestKnownBlock);

        uint256 endBlockNumber = Tronlib.blockIdToNumber(endBlock);
        require(params.relay.blocks(endBlockNumber) == endBlock);
        require(endBlockNumber < params.relay.latestBlock() - 18);
        require(startOrder == latestKnownOrder);
        require(oldStateHash == stateHash);
        require(_feePerBlock == params.feePerBlock);

        require(_isLastAtTimestamp(endOrder, endBlockTimestamp));

        stateHash = newStateHash;
        latestKnownOrder = endOrder;

        require(sha256(abi.encode(closedOrders)) == closedOrdersHash);

        uint64 paymasterFine = 0;
        for (uint256 i = 0; i < closedOrders.length; i++) {
            ClosedOrder memory state = closedOrders[i];
            Order memory order = activeOrders[state.tronAddress];

            uint64 amount = order.size < state.inflow ? order.size : state.inflow;
            amount = amount * 1e6 / order.rate;
            uint64 _paymasterFine = params.feePerBlock * ORDER_TTL - amount;

            uint64 left = order.size - amount;
            buyers[evmAddresses[state.tronAddress]].liquidity += left;

            amount -= params.feePerBlock * ORDER_TTL;
            amount -= params.revealerFee;

            // TODO: Paymaster fine is unused
            paymasterFine += _paymasterFine;
            if (order.fulfilledAmount + params.fulfillerFee == amount) {
                require(usdt.transfer(order.fulfiller, amount));
            } else {
                params.sender.send(amount, order.transferData);
            }

            _canCreateOrder[order.by] = true;
        }
        totalFee += params.revealerFee * uint64(closedOrders.length);

        require(usdt.transfer(msg.sender, totalFee));
    }

    function jailbreak() external {
        require(params.relay.latestBlock() > Tronlib.blockIdToNumber(latestKnownBlock) + 600); // 30 minutes
        params.relayer = address(0);
    }
}
