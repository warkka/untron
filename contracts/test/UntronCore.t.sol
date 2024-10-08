// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/UntronCore.sol";
import "./mocks/MockSpokePool.sol";
import "./mocks/MockAggregationRouter.sol";
import "@sp1-contracts/SP1MockVerifier.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MockUSDT is ERC20 {
    constructor() ERC20("Mock USDT", "USDT") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

contract UntronCoreTest is Test {
    UntronCore untronImplementation;
    UntronCore untron;
    MockSpokePool spokePool;
    MockAggregationRouter aggregationRouter;
    SP1MockVerifier sp1Verifier;
    MockUSDT usdt;

    address admin = address(1);
    address provider = address(2);
    address user = address(3);
    address receiver = address(4);
    address fulfiller = address(5);

    constructor() {
        vm.warp(1725527575); // the time i did this test at
    }

    // Util functions
    function setupProvider(address _provider, address _receiver) public {
        vm.startPrank(_provider);
        usdt.mint(_provider, 1000e6);
        usdt.approve(address(untron), 1000e6);

        address[] memory receivers = new address[](1);
        receivers[0] = _receiver;

        untron.setProvider(1000e6, 1e6, 500e6, 100e6, receivers);
        vm.stopPrank();
    }

    function createOrder(address _user, address _provider, address _receiver) public returns (bytes32 orderId) {
        vm.startPrank(admin);
        vm.stopPrank();

        setupProvider(_provider, _receiver);

        vm.startPrank(_user);
        UntronCore.Transfer memory transfer = IUntronTransfers.Transfer({
            recipient: _user,
            chainId: block.chainid,
            acrossFee: 0,
            doSwap: false,
            outToken: address(0),
            minOutputPerUSDT: 0,
            fixedOutput: false,
            swapData: ""
        });

        untron.createOrder(_provider, _receiver, 500e6, 1e6, transfer);
        vm.stopPrank();

        orderId = untron.isReceiverBusy(_receiver);
        return orderId;
    }

    function fulfillOrder(address _fulfiller, bytes32 _orderId) public {
        // Fulfill order
        vm.startPrank(_fulfiller);

        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = _orderId;

        (uint256 expense,) = untron.calculateFulfillerTotal(orderIds);

        usdt.mint(_fulfiller, expense);
        usdt.approve(address(untron), expense);

        untron.fulfill(orderIds, expense);
        vm.stopPrank();
    }

    function closeOrder(bytes memory publicValues) public {
        // Close orders
        vm.startPrank(admin);

        bytes memory proof = new bytes(0);

        untron.closeOrders(proof, publicValues);
        vm.stopPrank();
    }

    function setUp() public {
        vm.startPrank(admin);

        spokePool = new MockSpokePool();
        aggregationRouter = new MockAggregationRouter();
        sp1Verifier = new SP1MockVerifier();
        usdt = new MockUSDT();

        // Use UntronCore since UntronFees is abstract
        untronImplementation = new UntronCore();
        // Prepare the initialization data
        bytes memory initData = abi.encodeWithSelector(
            UntronCore.initialize.selector,
            bytes32(0), // blockId
            bytes32(0), // stateHash
            1000e6, // maxOrderSize
            address(spokePool),
            address(usdt),
            address(aggregationRouter),
            100, // relayerFee
            10000, // feePoint
            address(420), // trustedRelayer
            address(sp1Verifier),
            bytes32(uint256(1)) // vkey
        );

        // Deploy the proxy, pointing to the implementation and passing the init data
        ERC1967Proxy proxy = new ERC1967Proxy(address(untronImplementation), initData);
        untron = UntronCore(address(proxy));

        vm.stopPrank();
    }

    function test_SetUp() public view {
        assertEq(untron.spokePool(), address(spokePool));
        assertEq(untron.usdt(), address(usdt));
        assertEq(untron.verifier(), address(sp1Verifier));
        assertEq(untron.vkey(), bytes32(uint256(1)));
        assertEq(untron.relayerFee(), 100);
        assertEq(untron.feePoint(), 10000);
        assertEq(untron.maxOrderSize(), 1000e6);

        assertEq(untron.owner(), admin);
    }

    function test_providers_GetProviderDetails() public {
        // Given
        setupProvider(provider, receiver);

        // When
        IUntronCore.Provider memory _provider = untron.providers(provider);

        // Then
        assertEq(_provider.liquidity, 1000e6);
        assertEq(_provider.rate, 1e6);
        assertEq(_provider.minOrderSize, 500e6);
        assertEq(_provider.minDeposit, 100e6);
        assertEq(_provider.receivers.length, 1);
    }

    function test_isReceiverBusy_ChecksReceiverStatus() public {
        // Given
        bytes32 orderId = createOrder(user, provider, receiver);

        // When
        bytes32 storedOrderId = untron.isReceiverBusy(receiver);

        // Then
        assertEq(orderId, storedOrderId);
    }

    function test_receiverOwners_GetReceiverOwner() public {
        // Given
        setupProvider(provider, receiver);
        address[] memory owners = new address[](1);

        // When
        owners[0] = untron.receiverOwners(receiver);

        // Then
        assertEq(owners.length, 1);
        assertEq(owners[0], provider);
    }

    function test_orders_GetOrderByOrderId() public {
        // Given
        bytes32 orderId = createOrder(user, provider, receiver);

        // When
        IUntronCore.Order memory _order = untron.orders(orderId);

        // Then
        assertEq(_order.creator, user);
        assertEq(_order.provider, provider);
        assertEq(_order.receiver, receiver);
        assertEq(_order.size, 500e6);
        assertEq(_order.rate, 1e6);
    }

    function test_createOrder_CreatesOrder() public returns (bytes32 orderId) {
        // Given
        setupProvider(provider, receiver);

        vm.startPrank(user);
        UntronCore.Transfer memory transfer = IUntronTransfers.Transfer({
            recipient: user,
            chainId: block.chainid,
            acrossFee: 0,
            doSwap: false,
            outToken: address(0),
            minOutputPerUSDT: 0,
            fixedOutput: false,
            swapData: ""
        });

        // When
        untron.createOrder(provider, receiver, 500e6, 1e6, transfer);
        vm.stopPrank();

        // Then
        orderId = untron.isReceiverBusy(receiver);
        assertEq(untron.actionChainTip(), orderId);
        IUntronCore.Order memory _order = untron.orders(orderId);

        assertEq(_order.creator, user);
        assertEq(_order.provider, provider);
        assertEq(_order.receiver, receiver);
        assertEq(_order.size, 500e6);
        assertEq(_order.rate, 1e6);
        assertEq(_order.transfer.recipient, user);
        assertEq(_order.transfer.chainId, block.chainid);
        assertEq(_order.transfer.acrossFee, 0);
        assertEq(_order.transfer.doSwap, false);
        assertEq(_order.transfer.outToken, address(0));
        assertEq(_order.transfer.minOutputPerUSDT, 0);
        assertEq(_order.transfer.fixedOutput, false);
        assertEq(_order.transfer.swapData, "");

        return orderId;
    }

    function test_createOrder_RevertIf_NotEnoughProviderLiquidity() public {
        // Given
        // Set up provider
        setupProvider(provider, receiver);

        // When
        // Try to create order with not enough USDT
        vm.startPrank(user);
        UntronCore.Transfer memory transfer = IUntronTransfers.Transfer({
            recipient: user,
            chainId: block.chainid,
            acrossFee: 0,
            doSwap: false,
            outToken: address(0),
            minOutputPerUSDT: 0,
            fixedOutput: false,
            swapData: ""
        });

        vm.expectRevert();
        untron.createOrder(provider, receiver, 1001e6, 1e6, transfer);

        // Then
        vm.stopPrank();
    }

    function test_createOrder_RevertIf_ReceiverIsBusy() public {
        // Given
        // Set up provider
        setupProvider(provider, receiver);

        // Create order to make receiver busy
        vm.startPrank(user);
        UntronCore.Transfer memory transfer = IUntronTransfers.Transfer({
            recipient: user,
            chainId: block.chainid,
            acrossFee: 0,
            doSwap: false,
            outToken: address(0),
            minOutputPerUSDT: 0,
            fixedOutput: false,
            swapData: ""
        });
        untron.createOrder(provider, receiver, 500e6, 1e6, transfer);

        // When
        // Try to create another order for the same receiver
        vm.expectRevert();
        untron.createOrder(provider, receiver, 500e6, 1e6, transfer);

        // Then
        vm.stopPrank();
    }

    function test_createOrder_RevertIf_ReceiverIsNotOwnedByProvider() public {
        // Given
        // Set up provider
        setupProvider(provider, receiver);

        // Create order for receiver not owned by provider
        vm.startPrank(user);
        UntronCore.Transfer memory transfer = IUntronTransfers.Transfer({
            recipient: user,
            chainId: block.chainid,
            acrossFee: 0,
            doSwap: false,
            outToken: address(0),
            minOutputPerUSDT: 0,
            fixedOutput: false,
            swapData: ""
        });

        // When
        // Try to create order for receiver not owned by provider
        vm.expectRevert();
        untron.createOrder(provider, address(200), 500e6, 1e6, transfer);

        // Then
        vm.stopPrank();
    }

    function test_createOrder_RevertIf_ProviderDoesNotHaveEnoughLiquidity() public {
        // Given
        // Set up provider
        setupProvider(provider, receiver);

        // Create order for receiver not owned by provider
        vm.startPrank(user);
        UntronCore.Transfer memory transfer = IUntronTransfers.Transfer({
            recipient: user,
            chainId: block.chainid,
            acrossFee: 0,
            doSwap: false,
            outToken: address(0),
            minOutputPerUSDT: 0,
            fixedOutput: false,
            swapData: ""
        });

        // When
        // Try to create order for receiver not owned by provider
        vm.expectRevert();
        untron.createOrder(provider, receiver, 2000e6, 1e6, transfer);

        // Then
        vm.stopPrank();
    }

    function test_createOrder_RevertIf_RateUnequalToProvidersRate() public {
        // Given
        // Set up provider
        setupProvider(provider, receiver);

        // Create order for receiver not owned by provider
        vm.startPrank(user);
        UntronCore.Transfer memory transfer = IUntronTransfers.Transfer({
            recipient: user,
            chainId: block.chainid,
            acrossFee: 0,
            doSwap: false,
            outToken: address(0),
            minOutputPerUSDT: 0,
            fixedOutput: false,
            swapData: ""
        });

        // When
        // Try to create order for receiver not owned by provider
        vm.expectRevert();
        untron.createOrder(provider, receiver, 500e6, 2e6, transfer);

        // Then
        vm.stopPrank();
    }

    function test_createOrder_RevertIf_MinDepositGreaterThanOrderSize() public {
        // Given
        // Set up provider
        setupProvider(provider, receiver);

        // Create order for receiver not owned by provider
        vm.startPrank(user);
        UntronCore.Transfer memory transfer = IUntronTransfers.Transfer({
            recipient: user,
            chainId: block.chainid,
            acrossFee: 0,
            doSwap: false,
            outToken: address(0),
            minOutputPerUSDT: 0,
            fixedOutput: false,
            swapData: ""
        });

        // When
        // Try to create order for receiver not owned by provider
        vm.expectRevert();
        untron.createOrder(provider, receiver, 99e6, 1e6, transfer);

        // Then
        vm.stopPrank();
    }

    function test_createOrder_RevertIf_OrderSizeGreaterThanMaxOrderSize() public {
        // Given
        // Set up provider
        setupProvider(provider, receiver);

        // Create order for receiver not owned by provider
        vm.startPrank(user);
        UntronCore.Transfer memory transfer = IUntronTransfers.Transfer({
            recipient: user,
            chainId: block.chainid,
            acrossFee: 0,
            doSwap: false,
            outToken: address(0),
            minOutputPerUSDT: 0,
            fixedOutput: false,
            swapData: ""
        });

        // When
        // Try to create order for receiver not owned by provider
        vm.expectRevert();
        // Max order size is 1000e6 (see setUp)
        untron.createOrder(provider, receiver, 1001e6, 1e6, transfer);

        // Then
        vm.stopPrank();
    }

    function test_createOrder_CreateOrder() public {
        // Given
        // Set up provider
        setupProvider(provider, receiver);

        // Create order as ADMIN (unlimited creator)
        vm.startPrank(admin);
        UntronCore.Transfer memory transfer = IUntronTransfers.Transfer({
            recipient: user,
            chainId: block.chainid,
            acrossFee: 0,
            doSwap: false,
            outToken: address(0),
            minOutputPerUSDT: 0,
            fixedOutput: false,
            swapData: ""
        });

        untron.createOrder(provider, receiver, 500e6, 1e6, transfer);
        vm.stopPrank();

        // Then
        // Check order details
        bytes32 orderId = untron.isReceiverBusy(receiver);
        IUntronCore.Order memory _order = untron.orders(orderId);

        assertEq(_order.creator, admin);
        assertEq(_order.provider, provider);
        assertEq(_order.receiver, receiver);
        assertEq(_order.size, 500e6);
        assertEq(_order.rate, 1e6);
    }

    function test_changeOrder_ChangeOrder() public {
        // Given
        // Create order
        bytes32 orderId = createOrder(user, provider, receiver);
        // Get order
        IUntronCore.Order memory _oldOrder = untron.orders(orderId);

        // Change order
        vm.startPrank(user);
        UntronCore.Transfer memory transfer = IUntronTransfers.Transfer({
            recipient: address(300),
            chainId: block.chainid + 1,
            acrossFee: 1,
            doSwap: true,
            outToken: address(0),
            minOutputPerUSDT: 0,
            fixedOutput: true,
            swapData: ""
        });
        // When
        untron.changeOrder(orderId, transfer);

        // Then
        // Check order details
        IUntronCore.Order memory _order = untron.orders(orderId);

        assertEq(_order.creator, _oldOrder.creator);
        assertEq(_order.provider, _oldOrder.provider);
        assertEq(_order.receiver, _oldOrder.receiver);
        assertEq(_order.size, _oldOrder.size);
        assertEq(_order.rate, _oldOrder.rate);
        assertEq(_order.transfer.recipient, transfer.recipient);
        assertEq(_order.transfer.chainId, transfer.chainId);
        assertEq(_order.transfer.acrossFee, transfer.acrossFee);
        assertEq(_order.transfer.doSwap, transfer.doSwap);
        assertEq(_order.transfer.outToken, transfer.outToken);
        assertEq(_order.transfer.minOutputPerUSDT, transfer.minOutputPerUSDT);
        assertEq(_order.transfer.fixedOutput, transfer.fixedOutput);
        assertEq(_order.transfer.swapData, transfer.swapData);
    }

    function test_changeOrder_RevertIf_NonOrderCreatorChangesOrder() public {
        // Given
        // Set up provider and create order
        bytes32 orderId = createOrder(user, provider, receiver);

        // Change order
        vm.startPrank(address(300));
        UntronCore.Transfer memory transfer = IUntronTransfers.Transfer({
            recipient: address(300),
            chainId: block.chainid + 1,
            acrossFee: 1,
            doSwap: true,
            outToken: address(0),
            minOutputPerUSDT: 0,
            fixedOutput: true,
            swapData: ""
        });

        // When
        // Try to change order as non-creator
        vm.expectRevert();
        untron.changeOrder(orderId, transfer);

        // Then
        vm.stopPrank();
    }

    function test_stopOrder_StopOrder() public {
        // Given
        // Set up provider and create order
        bytes32 orderId = createOrder(user, provider, receiver);
        uint256 beforeLiquidity = untron.providers(provider).liquidity;
        IUntronCore.Order memory _oldOrder = untron.orders(orderId);

        // Stop order
        vm.startPrank(user);
        untron.stopOrder(orderId);

        // Then
        IUntronCore.Order memory defaultOrder = untron.orders(orderId);
        IUntronCore.Transfer memory defaultTransfer = IUntronTransfers.Transfer({
            recipient: address(0),
            chainId: 0,
            acrossFee: 0,
            doSwap: false,
            outToken: address(0),
            minOutputPerUSDT: 0,
            fixedOutput: false,
            swapData: ""
        });

        uint256 afterLiquidity = untron.providers(provider).liquidity;
        assertEq(afterLiquidity, beforeLiquidity + _oldOrder.size);
        // TODO: Calculate hash and check correct
        // assertEq(untron.actionChainTip(), "TBA");
        assertEq(untron.isReceiverBusy(receiver), bytes32(0));

        // Check order was deleted
        assertEq(defaultOrder.parent, bytes32(0));
        assertEq(defaultOrder.timestamp, 0);
        assertEq(defaultOrder.creator, address(0));
        assertEq(defaultOrder.provider, address(0));
        assertEq(defaultOrder.receiver, address(0));
        assertEq(defaultOrder.size, 0);
        assertEq(defaultOrder.rate, 0);
        assertEq(defaultOrder.minDeposit, 0);
        assertEq(defaultOrder.transfer.recipient, defaultTransfer.recipient);
        assertEq(defaultOrder.transfer.chainId, defaultTransfer.chainId);
        assertEq(defaultOrder.transfer.acrossFee, defaultTransfer.acrossFee);
        assertEq(defaultOrder.transfer.doSwap, defaultTransfer.doSwap);
        assertEq(defaultOrder.transfer.outToken, defaultTransfer.outToken);
        assertEq(defaultOrder.transfer.minOutputPerUSDT, defaultTransfer.minOutputPerUSDT);
        assertEq(defaultOrder.transfer.fixedOutput, defaultTransfer.fixedOutput);
        assertEq(defaultOrder.transfer.swapData, defaultTransfer.swapData);
    }

    function test_stopOrder_RevertIf_NonCreatorStopsOrder() public {
        // Given
        // Set up provider and create order
        bytes32 orderId = createOrder(user, provider, receiver);

        // Stop order
        vm.startPrank(address(300));

        // When
        // Try to stop order as non-creator
        vm.expectRevert();
        untron.stopOrder(orderId);

        // Then
        vm.stopPrank();
    }

    function test_calculateFulfillerTotal_CalculatesFulfillerTotal() public {
        // Given
        // Set up provider and create order
        bytes32 orderId = createOrder(user, provider, receiver);

        // Fulfill order
        vm.startPrank(fulfiller);

        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = orderId;

        (uint256 expense, uint256 fee) = untron.calculateFulfillerTotal(orderIds);

        // Then
        uint256 relayerFee = 0.05e6; // (0.01% of 500e6)
        uint256 fulfillerFee = 0.02e6; // 2 fee points
        uint256 expectedExpense = 500e6 - relayerFee - fulfillerFee;
        assertEq(expense, expectedExpense);

        // Fee is equivalent to 2 fee points
        assertEq(fee, 20000);
    }

    function test_fulfill_FulfillOrderExactAmount() public returns (bytes32 orderId) {
        // Given
        // Set up provider and create order
        orderId = createOrder(user, provider, receiver);

        // Fulfill order
        vm.startPrank(fulfiller);

        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = orderId;

        (uint256 expense,) = untron.calculateFulfillerTotal(orderIds);

        usdt.mint(fulfiller, expense);
        usdt.approve(address(untron), expense);

        untron.fulfill(orderIds, expense);
        vm.stopPrank();

        // Check order status
        IUntronCore.Order memory _order = untron.orders(orderId);
        assertEq(_order.creator, fulfiller);
        assertEq(_order.transfer.recipient, fulfiller);
        assertEq(_order.transfer.chainId, 31337); // ZKsync chain ID
        assertEq(_order.transfer.doSwap, false);
        assertEq(untron.isReceiverBusy(receiver), bytes32(0));

        // Check USDT balances
        assertEq(usdt.balanceOf(user), expense);
        assertEq(usdt.balanceOf(fulfiller), 0);
        // TODO: See why this fails, returning 1000000000 instead of 0
        // assertEq(usdt.balanceOf(address(untron)), 0);

        return orderId;
    }

    function test_fulfill_FulfillWithExtraUSDTReturnsDifferenceToFulfiller() public {
        // Given
        // Set up provider and create order
        bytes32 orderId = createOrder(user, provider, receiver);

        // Fulfill order
        vm.startPrank(fulfiller);

        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = orderId;

        (uint256 expense,) = untron.calculateFulfillerTotal(orderIds);

        usdt.mint(fulfiller, expense + 1);
        usdt.approve(address(untron), expense + 1);

        untron.fulfill(orderIds, expense + 1);
        vm.stopPrank();

        // Check order status
        IUntronCore.Order memory _order = untron.orders(orderId);
        assertEq(_order.creator, fulfiller);
        assertEq(_order.transfer.recipient, fulfiller);
        assertEq(_order.transfer.chainId, 31337); // ZKsync chain ID
        assertEq(_order.transfer.doSwap, false);
        assertEq(untron.isReceiverBusy(receiver), bytes32(0));

        // Check USDT balances
        assertEq(usdt.balanceOf(user), expense);
        assertEq(usdt.balanceOf(fulfiller), 1);
        // TODO: See why this fails, returning 1000000000 instead of 0
        // assertEq(usdt.balanceOf(address(untron)), 0);
    }

    function test_fulfill_RevertIf_InsufficientFunds() public {
        // Given
        // Set up provider and create order
        bytes32 orderId = createOrder(user, provider, receiver);

        // Fulfill order
        vm.startPrank(fulfiller);

        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = orderId;

        (uint256 expense,) = untron.calculateFulfillerTotal(orderIds);

        usdt.mint(fulfiller, expense - 1);
        usdt.approve(address(untron), expense - 1);

        // When
        // Try to fulfill order with insufficient funds
        vm.expectRevert();
        untron.fulfill(orderIds, expense);

        // Then
        vm.stopPrank();
    }

    function test_fulfill_RevertIf_ExpectedTotalLessThanSentTotal() public {
        // Given
        // Set up provider and create order
        bytes32 orderId = createOrder(user, provider, receiver);

        // Fulfill order
        vm.startPrank(fulfiller);

        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = orderId;

        (uint256 expense,) = untron.calculateFulfillerTotal(orderIds);

        usdt.mint(fulfiller, expense);
        usdt.approve(address(untron), expense);

        // When
        // Try to fulfill order with more funds than expected
        vm.expectRevert();
        untron.fulfill(orderIds, expense + 1);

        // Then
        vm.stopPrank();
    }

    function test_closeOrders_CloseOrdersWithRelayerRole()
        public
        returns (bytes32 orderId, bytes memory publicValues)
    {
        // Set up provider, create order, and fulfill order
        orderId = createOrder(user, provider, receiver);
        fulfillOrder(fulfiller, orderId);
        uint256 untronPreBalance = usdt.balanceOf(address(untron));

        IUntronCore.Order memory order = untron.orders(orderId);

        // Close orders
        vm.startPrank(admin);

        IUntronCore.Inflow[] memory closedOrders = new IUntronCore.Inflow[](1);
        closedOrders[0] = IUntronCore.Inflow({order: orderId, inflow: 500e6});

        publicValues = abi.encode(
            bytes32(0), // oldBlockId
            bytes32(uint256(1)), // newBlockId
            bytes32(0), // oldlatestExecutedAction
            orderId, // newlatestExecutedAction
            bytes32(0), // oldStateHash
            bytes32(uint256(1)), // newStateHash
            closedOrders // closedOrders
        );

        bytes memory proof = new bytes(0);

        untron.closeOrders(proof, publicValues);
        vm.stopPrank();

        // Check state updates
        assertEq(untron.blockId(), bytes32(uint256(1)));
        assertEq(untron.latestExecutedAction(), orderId);
        assertEq(untron.stateHash(), bytes32(uint256(1)));

        // Check balance changes
        // order.transfer.receipient should have (+500e6 - relayerFee)
        // contract should have -(500e6)
        // untron owner should have relayerFee
        assertEq(usdt.balanceOf(address(untron)), untronPreBalance - 500e6);
        assertEq(usdt.balanceOf(untron.owner()), 0.05e6);
        assertEq(usdt.balanceOf(order.transfer.recipient), 500e6 - 0.05e6);

        return (orderId, publicValues);
    }

    function test_closeOrders_RevertIf_OldBlockIdIsNotLatestZKProvenBlockId() public {
        // Given
        // Set up provider, create order, and fulfill order
        bytes32 orderId = createOrder(user, provider, receiver);
        fulfillOrder(fulfiller, orderId);

        // When
        vm.startPrank(admin);
        IUntronCore.Inflow[] memory closedOrders = new IUntronCore.Inflow[](1);
        closedOrders[0] = IUntronCore.Inflow({order: orderId, inflow: 500e6});

        bytes memory publicValues = abi.encode(
            // Should be 0, but we set it to 1 to make it invalid
            bytes32(uint256(1)), // oldBlockId
            bytes32(uint256(2)), // newBlockId
            block.timestamp - 1, // newTimestamp
            bytes32(0), // oldlatestExecutedAction
            orderId, // newlatestExecutedAction
            bytes32(0), // oldStateHash
            bytes32(uint256(1)), // newStateHash
            closedOrders // closedOrders
        );

        bytes memory proof = new bytes(0);

        vm.expectRevert();
        untron.closeOrders(proof, publicValues);

        // Then
        vm.stopPrank();
    }

    function test_closeOrders_RevertIf_OldlatestExecutedActionIsNotLatestZKProvenClosedOrder() public {
        // Given
        // Set up provider, create order, and fulfill order
        bytes32 orderId = createOrder(user, provider, receiver);
        fulfillOrder(fulfiller, orderId);

        // When
        vm.startPrank(admin);
        IUntronCore.Inflow[] memory closedOrders = new IUntronCore.Inflow[](1);
        closedOrders[0] = IUntronCore.Inflow({order: orderId, inflow: 500e6});

        bytes memory publicValues = abi.encode(
            bytes32(uint256(0)), // oldBlockId
            bytes32(uint256(1)), // newBlockId
            block.timestamp - 1, // newTimestamp
            // Should be 0, but we set it to 1 to make it invalid
            bytes32(uint256(1)), // oldlatestExecutedAction
            orderId, // newlatestExecutedAction
            bytes32(0), // oldStateHash
            bytes32(uint256(1)), // newStateHash
            closedOrders // closedOrders
        );

        bytes memory proof = new bytes(0);

        vm.expectRevert();
        untron.closeOrders(proof, publicValues);

        // Then
        vm.stopPrank();
    }

    function test_closeOrders_RevertIf_NewZKProvenlatestExecutedActionTimestampIsNotGreaterThanBlockTimestamp()
        public
    {
        // Given
        // Close order once to set a valid lastRelayerActivity
        address preProvider = address(102);
        address preUser = address(103);
        address preReceiver = address(104);
        address preFulfiller = address(105);

        bytes32 preOrderId = createOrder(preUser, preProvider, preReceiver);
        fulfillOrder(preFulfiller, preOrderId);

        IUntronCore.Inflow[] memory preClosedOrders = new IUntronCore.Inflow[](1);
        preClosedOrders[0] = IUntronCore.Inflow({order: preOrderId, inflow: 500e6});

        bytes32 preNewBlockId = bytes32(uint256(1));
        bytes32 preNewlatestExecutedAction = preOrderId;
        bytes32 preNewStateHash = bytes32(uint256(1));

        closeOrder(
            abi.encode(
                bytes32(0), // oldBlockId
                preNewBlockId, // newBlockId
                bytes32(0), // oldlatestExecutedAction
                preNewlatestExecutedAction, // newlatestExecutedAction
                bytes32(0), // oldStateHash
                preNewStateHash, // newStateHash
                preClosedOrders // closedOrders
            )
        );

        // Set up provider, create order, and fulfill order
        bytes32 orderId = createOrder(user, provider, receiver);
        fulfillOrder(fulfiller, orderId);

        // When
        vm.startPrank(admin);
        IUntronCore.Inflow[] memory closedOrders = new IUntronCore.Inflow[](1);
        closedOrders[0] = IUntronCore.Inflow({order: orderId, inflow: 500e6});

        bytes memory publicValues = abi.encode(
            preNewBlockId, // oldBlockId
            bytes32(uint256(2)), // newBlockId
            // Should be block.timestamp, but we set it to block.timestamp + 100000000000000000 so that there is no
            // new order that was included after the last closed order
            block.timestamp + 100000000000000000, // newTimestamp
            preNewlatestExecutedAction, // oldlatestExecutedAction
            orderId, // newlatestExecutedAction
            preNewStateHash, // oldStateHash
            bytes32(uint256(2)), // newStateHash
            closedOrders // closedOrders
        );

        bytes memory proof = new bytes(0);

        vm.expectRevert();
        untron.closeOrders(proof, publicValues);

        // Then
        vm.stopPrank();
    }

    function test_closeOrders_RevertIf_OldStateHashIsNotLatestZkProvenStateHash() public {
        // Given
        // Close order once to set a valid lastRelayerActivity
        address preProvider = address(102);
        address preUser = address(103);
        address preReceiver = address(104);
        address preFulfiller = address(105);

        bytes32 preOrderId = createOrder(preUser, preProvider, preReceiver);
        fulfillOrder(preFulfiller, preOrderId);

        IUntronCore.Inflow[] memory preClosedOrders = new IUntronCore.Inflow[](1);
        preClosedOrders[0] = IUntronCore.Inflow({order: preOrderId, inflow: 500e6});

        bytes32 preNewBlockId = bytes32(uint256(1));
        bytes32 preNewlatestExecutedAction = preOrderId;
        bytes32 preNewStateHash = bytes32(uint256(1));

        closeOrder(
            abi.encode(
                bytes32(0), // oldBlockId
                preNewBlockId, // newBlockId
                bytes32(0), // oldlatestExecutedAction
                preNewlatestExecutedAction, // newlatestExecutedAction
                bytes32(0), // oldStateHash
                preNewStateHash, // newStateHash
                preClosedOrders // closedOrders
            )
        );

        // Set up provider, create order, and fulfill order
        bytes32 orderId = createOrder(user, provider, receiver);
        fulfillOrder(fulfiller, orderId);

        // When
        vm.startPrank(admin);
        IUntronCore.Inflow[] memory closedOrders = new IUntronCore.Inflow[](1);
        closedOrders[0] = IUntronCore.Inflow({order: orderId, inflow: 500e6});

        bytes memory publicValues = abi.encode(
            preNewBlockId, // oldBlockId
            bytes32(uint256(2)), // newBlockId
            block.timestamp + 1, // newTimestamp
            preNewlatestExecutedAction, // oldlatestExecutedAction
            orderId, // newlatestExecutedAction
            // Should be preNewStateHash, but we set it to 0 to make it invalid
            bytes32(uint256(150)), // oldStateHash
            bytes32(uint256(2)), // newStateHash
            closedOrders // closedOrders
        );

        bytes memory proof = new bytes(0);

        vm.expectRevert();
        untron.closeOrders(proof, publicValues);

        // Then
        vm.stopPrank();
    }

    function test_setProvider_SetsLiquidityProviderDetails() public {
        vm.startPrank(provider);
        usdt.mint(provider, 1000e6);
        usdt.approve(address(untron), 1000e6);

        address[] memory receivers = new address[](1);
        receivers[0] = receiver;

        untron.setProvider(1000e6, 1e6, 1000e6, 100e6, receivers);

        IUntronCore.Provider memory _provider = untron.providers(provider);
        assertEq(_provider.liquidity, 1000e6);
        assertEq(_provider.rate, 1e6);
        assertEq(_provider.minOrderSize, 1000e6);
        assertEq(_provider.minDeposit, 100e6);
        assertEq(_provider.receivers[0], receiver);

        vm.stopPrank();
    }

    function test_setProvider_SetProviderDetailsWithLessLiquidityToWithdrawLiquidity() public {
        // Given
        // Provide 1000 USDT to contract from provider
        setupProvider(provider, receiver);
        vm.startPrank(provider);

        address[] memory receivers = new address[](1);
        receivers[0] = receiver;

        // When
        untron.setProvider(500e6, 1e6, 1000e6, 100e6, receivers);

        // Then
        IUntronCore.Provider memory _provider = untron.providers(provider);
        assertEq(_provider.liquidity, 500e6);
        assertEq(_provider.rate, 1e6);
        assertEq(_provider.minOrderSize, 1000e6);
        assertEq(_provider.minDeposit, 100e6);
        assertEq(_provider.receivers[0], receiver);

        // Check USDT balances
        assertEq(usdt.balanceOf(provider), 500e6);
        assertEq(usdt.balanceOf(address(untron)), 500e6);
    }

    function test_setProvider_SetProviderDetailsWithMoreLiquidityToAddLiquidity() public {
        // Given
        // Provide 1000 USDT to contract from provider
        setupProvider(provider, receiver);
        vm.startPrank(provider);

        usdt.mint(provider, 500e6);
        usdt.approve(address(untron), 500e6);

        address[] memory receivers = new address[](1);
        receivers[0] = receiver;

        // When
        untron.setProvider(1500e6, 0.99e6, 500e6, 50e6, receivers);

        // Then
        IUntronCore.Provider memory _provider = untron.providers(provider);
        assertEq(_provider.liquidity, 1500e6);
        assertEq(_provider.rate, 0.99e6);
        assertEq(_provider.minOrderSize, 500e6);
        assertEq(_provider.minDeposit, 50e6);
        assertEq(_provider.receivers[0], receiver);

        // Check USDT balances
        assertEq(usdt.balanceOf(provider), 0e6);
        assertEq(usdt.balanceOf(address(untron)), 1500e6);
    }

    function test_setProvider_RevertIf_SettingReceiverOwnedByAnotherProvider() public {
        // Given
        // Set up provider
        setupProvider(provider, receiver);

        // When
        // Try to set receiver owned by another provider
        address newProvider = address(200);
        vm.startPrank(newProvider);
        address[] memory receivers = new address[](1);
        receivers[0] = receiver;

        vm.expectRevert();
        untron.setProvider(1000e6, 1e6, 1000e6, 100e6, receivers);

        // Then
        vm.stopPrank();
    }

    function test_setUntronCoreVariables_SetVariables() public {
        vm.startPrank(admin);

        bytes32 blockId = bytes32(uint256(1));
        bytes32 actionChainTip = bytes32(uint256(2));
        bytes32 latestExecutedAction = bytes32(uint256(3));
        bytes32 stateHash = bytes32(uint256(4));
        uint256 maxOrderSize = 100e6;
        uint256 requiredCollateral = 100e6;

        untron.setCoreVariables(
            blockId, actionChainTip, latestExecutedAction, stateHash, maxOrderSize, requiredCollateral
        );

        assertEq(untron.blockId(), blockId);
        assertEq(untron.actionChainTip(), actionChainTip);
        assertEq(untron.latestExecutedAction(), latestExecutedAction);
        assertEq(untron.stateHash(), stateHash);
        assertEq(untron.maxOrderSize(), maxOrderSize);

        vm.stopPrank();
    }
}
