// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISP1Verifier} from "@sp1-contracts/ISP1Verifier.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./interfaces/IUntron.sol";
import "./Tronlib.sol";

contract Untron is IUntron, Ownable {
    IERC20 constant usdt = IERC20(0x493257fD37EDB34451f62EDf8D2a0C418852bA4C); // bridged USDT @ zksync era

    constructor() Ownable(msg.sender) {}

    uint64 constant ORDER_TTL = 100; // 100 blocks = 5 min

    Params internal _params;

    function params() external view returns (Params memory) {
        return _params;
    }

    function params(Params calldata __params) public onlyOwner {
        _params = __params;
    }

    bytes32 public stateHash = bytes32(0xe3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855); // sha256("")
    bytes32 public latestKnownBlock;
    bytes32 public latestKnownOrder;

    bytes32 public latestOrder;
    uint256 public totalOrders;

    uint256[] public orderTimestamps; // order index -> timestamp
    mapping(bytes32 => uint256) public orderIndexes;
    mapping(address => Order) internal _activeOrders; // tron address -> Order
    mapping(address => address) public evmAddresses; // tron address -> evm address
    mapping(address => Buyer) internal _buyers; // EVM address -> Buyer
    mapping(address => uint256) public orderCount; // tron address -> order count

    function activeOrders(address tronAddress) external view returns (Order memory) {
        return _activeOrders[tronAddress];
    }

    function buyers(address evmAddress) external view returns (Buyer memory) {
        return _buyers[evmAddress];
    }

    struct OrderChain {
        bytes32 prev;
        uint32 timestamp;
        address tronAddress;
        uint64 minDeposit;
    }

    function setBuyer(uint64 liquidity, uint64 rate, uint64 minDeposit) external {
        require(usdt.transferFrom(msg.sender, address(this), liquidity));

        _buyers[msg.sender].active = true;
        _buyers[msg.sender].liquidity += liquidity;
        _buyers[msg.sender].rate = rate;
        _buyers[msg.sender].minDeposit = minDeposit;
    }

    function closeBuyer() external {
        require(usdt.transfer(msg.sender, _buyers[msg.sender].liquidity));

        delete _buyers[msg.sender];
    }

    mapping(address => uint256[]) internal userActions; // address -> timestamps of actions
    // checks whether the user can
    // create an order. when they can't, it must be false,
    // and vice versa. by default, all users can't
    // unless they register and this is set to true.
    // this is made like this to save storage slots.
    mapping(address => bool) internal _canCreateOrder;

    function canCreateOrder(address who) external view returns (bool) {
        return _canCreateOrder[who];
    }

    function register(bytes calldata registrarSig) external {
        require(ECDSA.recover(bytes32(uint256(uint160(msg.sender))), registrarSig) == _params.registrar);
        require(userActions[msg.sender].length == 0);
        _canCreateOrder[msg.sender] = true;
    }

    function createOrder(address tronAddress, uint64 size, bytes calldata transferData) external {
        require(_canCreateOrder[msg.sender]);
        require(
            userActions[msg.sender][userActions[msg.sender].length - _params.rateLimit] + _params.limitPer
                < block.timestamp
        );
        require(size >= _params.minSize);
        require(_activeOrders[tronAddress].size == 0);

        address buyer = evmAddresses[tronAddress];
        require(_buyers[buyer].active);
        require(_buyers[buyer].liquidity >= size);
        _buyers[buyer].liquidity -= size;

        _activeOrders[tronAddress] = Order({
            by: msg.sender,
            size: size,
            rate: _buyers[buyer].rate,
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
                    minDeposit: _buyers[buyer].minDeposit
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

            if (_activeOrders[tronAddress].fulfilledAmount != 0) {
                continue; // not require bc someone could fulfill ahead of them
            }

            uint64 amount = amounts[i];
            require(usdt.transferFrom(msg.sender, address(this), amount));

            _params.sender.send(amount, _activeOrders[tronAddress].transferData);
            _activeOrders[tronAddress].fulfiller = msg.sender;
            _activeOrders[tronAddress].fulfilledAmount = amount;
        }
    }

    function _isLastAtTimestamp(bytes32 order, uint32 timestamp) internal view returns (bool) {
        uint256 orderIndex = orderIndexes[order];
        return (
            orderTimestamps[orderIndex] <= timestamp
                && (orderIndex == orderTimestamps.length - 1 || orderTimestamps[orderIndex + 1] > timestamp)
        );
    }

    function revealDeposits(bytes calldata proof, bytes calldata publicValues, ClosedOrder[] calldata closedOrders)
        external
    {
        require(msg.sender == _params.relayer || _params.relayer == address(0));

        _params.verifier.verifyProof(_params.vkey, publicValues, proof);
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
        require(_params.relay.blocks(endBlockNumber) == endBlock);
        require(endBlockNumber < _params.relay.latestBlockNumber() - 18);
        require(startOrder == latestKnownOrder);
        require(oldStateHash == stateHash);
        require(_feePerBlock == _params.feePerBlock);

        require(_isLastAtTimestamp(endOrder, endBlockTimestamp));

        stateHash = newStateHash;
        latestKnownOrder = endOrder;

        require(sha256(abi.encode(closedOrders)) == closedOrdersHash);
        for (uint256 i = 0; i < closedOrders.length; i++) {
            ClosedOrder memory state = closedOrders[i];
            Order memory order = _activeOrders[state.tronAddress];

            uint64 amount = order.size < state.inflow ? order.size : state.inflow;
            amount = amount * 1e6 / order.rate;

            uint64 left = order.size - amount;
            _buyers[evmAddresses[state.tronAddress]].liquidity += left;

            amount -= _params.feePerBlock * ORDER_TTL;
            amount -= _params.revealerFee;

            if (order.fulfilledAmount + _params.fulfillerFee == amount) {
                require(usdt.transfer(order.fulfiller, amount));
            } else {
                _params.sender.send(amount, order.transferData);
            }

            _canCreateOrder[order.by] = true;
        }
        totalFee += _params.revealerFee * uint64(closedOrders.length);

        require(usdt.transfer(msg.sender, totalFee));
    }

    function jailbreak() external {
        require(_params.relay.latestBlockNumber() > Tronlib.blockIdToNumber(latestKnownBlock) + 600); // 30 minutes
        _params.relayer = address(0);
    }
}
