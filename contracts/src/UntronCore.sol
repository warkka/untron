// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "./interfaces/IUntronCore.sol";
import "./UntronTransfers.sol";
import "./UntronTools.sol";
import "./UntronFees.sol";
import "./UntronZK.sol";

contract UntronCore is IUntronCore, Initializable, UntronTransfers, UntronFees, UntronZK, UUPSUpgradeable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _spokePool, address _usdt, address _swapper) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        __UntronState_init();
        __UntronTransfers_init(_spokePool, _usdt, _swapper);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);
    }

    mapping(address => Provider) providers;
    mapping(address => bytes32) isReceiverBusy;
    mapping(address => address) receiverOwners;
    mapping(bytes32 => Order) orders;

    function calculateTotal(address[] calldata _receivers)
        external
        view
        returns (uint256 totalExpense, uint256 totalIncome)
    {
        for (uint256 i = 0; i < _receivers.length; i++) {
            bytes32 activeOrderHash = isReceiverBusy[_receivers[i]];
            Order memory order = orders[activeOrderHash];

            uint256 fulfillerFee = calculateFee(order.transfer.doSwap, order.transfer.chainId);
            (uint256 amount,) = conversion(order.size, order.rate, fulfillerFee);

            totalExpense += amount;
            totalIncome += fulfillerFee;
        }
    }

    function fulfill(address[] calldata _receivers, uint256 total) external {
        internalTransferFrom(msg.sender, total);
        uint256 supposedTotal;

        for (uint256 i = 0; i < _receivers.length; i++) {
            bytes32 activeOrderHash = isReceiverBusy[_receivers[i]];
            Order memory order = orders[activeOrderHash];

            uint256 fulfillerFee = calculateFee(order.transfer.doSwap, order.transfer.chainId);
            (uint256 amount,) = conversion(order.size, order.rate, fulfillerFee);
            supposedTotal += amount;

            smartTransfer(order.transfer, amount);

            uint256 _chainId = chainId();
            orders[activeOrderHash].transfer.recipient = msg.sender;
            orders[activeOrderHash].transfer.chainId = _chainId;
            orders[activeOrderHash].transfer.doSwap = false; // TODO: explain why
            delete isReceiverBusy[_receivers[i]];
        }

        require(total == supposedTotal);
    }

    mapping(bytes32 => uint256) internal orderTimestamps; // order hash -> timestamp

    function closeOrders(bytes calldata proof, bytes calldata publicValues) external {
        verifyProof(publicValues, proof);

        (
            bytes32 oldBlockId,
            bytes32 newBlockId,
            uint256 newTimestamp,
            bytes32 oldOrderChain,
            bytes32 newOrderChain,
            bytes32 oldStateHash,
            bytes32 newStateHash,
            Inflow[] memory closedOrders
        ) = abi.decode(publicValues, (bytes32, bytes32, uint256, bytes32, bytes32, bytes32, bytes32, Inflow[]));

        require(oldBlockId == blockId);
        require(oldOrderChain == latestClosedOrder);
        require(orderTimestamps[newOrderChain] >= newTimestamp);
        require(oldStateHash == stateHash);

        blockId = newBlockId;
        latestClosedOrder = newOrderChain;
        stateHash = newStateHash;

        uint256 totalFee;

        for (uint256 i = 0; i < closedOrders.length; i++) {
            bytes32 orderHash = closedOrders[i].order;

            uint256 inflow =
                closedOrders[i].inflow < orders[orderHash].size ? closedOrders[i].inflow : orders[orderHash].size;

            (uint256 amount, uint256 fee) = conversion(inflow, orders[orderHash].rate, 0);
            totalFee += fee;

            smartTransfer(orders[orderHash].transfer, amount);
        }

        internalTransfer(msg.sender, totalFee);
    }

    function createOrder(
        address creator,
        address provider,
        address receiver,
        uint256 size,
        uint256 rate,
        Transfer calldata transfer
    ) external ratePer(rate, per, true) {
        require(isReceiverBusy[receiver] == bytes32(0));
        require(receiverOwners[receiver] == provider);
        require(providers[provider].liquidity >= size);
        require(rate == providers[provider].rate);
        providers[provider].liquidity -= size;

        bytes32 orderHash = sha256(abi.encode(latestOrder, block.timestamp, receiver, providers[provider].minDeposit));
        latestOrder = orderHash;
        orderTimestamps[orderHash] = uint64(block.timestamp);
        isReceiverBusy[receiver] = orderHash;
        orders[orderHash] = Order({creator: creator, size: size, rate: rate, transfer: transfer});
    }

    function changeOrder(bytes32 orderHash, Transfer calldata transfer) external {
        require(orders[orderHash].creator == msg.sender);
        require(orderTimestamps[orderHash] + 60 <= block.timestamp);

        orders[orderHash].transfer = transfer;
    }

    function setProvider(uint256 liquidity, uint256 rate, uint256 minDeposit, address[] calldata receivers) external {
        uint256 currentLiquidity = providers[msg.sender].liquidity;

        if (currentLiquidity < liquidity) {
            internalTransferFrom(msg.sender, liquidity - currentLiquidity);
        } else if (currentLiquidity > liquidity) {
            internalTransfer(msg.sender, currentLiquidity - liquidity);
        }
        providers[msg.sender].liquidity = liquidity;

        providers[msg.sender].rate = rate;
        providers[msg.sender].minDeposit = minDeposit;
        providers[msg.sender].receivers = receivers;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}
}
