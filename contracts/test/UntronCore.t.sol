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

    function setUp() public {
        vm.startPrank(admin);

        spokePool = new MockSpokePool();
        aggregationRouter = new MockAggregationRouter();
        sp1Verifier = new SP1MockVerifier();
        usdt = new MockUSDT();

        untronImplementation = new UntronCore();
        // Prepare the initialization data
        bytes memory initData = abi.encodeWithSelector(
            UntronCore.initialize.selector, address(spokePool), address(usdt), address(aggregationRouter)
        );

        // Deploy the proxy, pointing to the implementation and passing the init data
        ERC1967Proxy proxy = new ERC1967Proxy(address(untronImplementation), initData);
        untron = UntronCore(address(proxy));

        untron.setUntronZKVariables(address(sp1Verifier), bytes32(0));
        untron.register(user, ""); // we're registrar so we don't need signature

        vm.stopPrank();

        assertEq(untron.hasRole(untron.DEFAULT_ADMIN_ROLE(), admin), true);
        assertEq(untron.hasRole(untron.UPGRADER_ROLE(), admin), true);
        assertEq(untron.hasRole(untron.UNLIMITED_CREATOR_ROLE(), admin), true);
    }

    function testSetProvider() public {
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

    function testCreateOrder() public returns (bytes32 orderId) {
        // Set up provider
        vm.startPrank(provider);
        usdt.mint(provider, 1000e6);
        usdt.approve(address(untron), 1000e6);

        address[] memory receivers = new address[](1);
        receivers[0] = receiver;

        untron.setProvider(1000e6, 1e6, 500e6, 100e6, receivers);
        vm.stopPrank();

        // Create order
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
        vm.stopPrank();

        // Check order details
        orderId = untron.isReceiverBusy(receiver);
        IUntronCore.Order memory _order = untron.orders(orderId);

        assertEq(_order.creator, user);
        assertEq(_order.provider, provider);
        assertEq(_order.receiver, receiver);
        assertEq(_order.size, 500e6);
        assertEq(_order.rate, 1e6);

        return orderId;
    }

    function testFulfillOrder() public returns (bytes32 orderId) {
        // Set up provider and create order
        orderId = testCreateOrder();

        // Fulfill order
        vm.startPrank(fulfiller);

        address[] memory receivers = new address[](1);
        receivers[0] = receiver;

        (uint256 expense, uint256 profit) = untron.calculateFulfillerTotal(receivers);
        console.log("expense", expense);
        console.log("profit", profit);

        usdt.mint(fulfiller, expense);
        usdt.approve(address(untron), expense);

        untron.fulfill(receivers, expense);
        vm.stopPrank();

        // Check order status
        assertEq(untron.isReceiverBusy(receiver), bytes32(0));

        // Check USDT balances
        assertEq(usdt.balanceOf(user), expense);
        assertEq(usdt.balanceOf(fulfiller), 0);

        return orderId;
    }

    function testCloseOrders() public {
        // Set up provider, create order, and fulfill order
        bytes32 orderId = testFulfillOrder();

        // Close orders
        vm.startPrank(admin);
        untron.grantRole(untron.RELAYER_ROLE(), admin);

        IUntronCore.Inflow[] memory closedOrders = new IUntronCore.Inflow[](1);
        closedOrders[0] = IUntronCore.Inflow({order: orderId, inflow: 500e6});

        bytes memory publicValues = abi.encode(
            bytes32(0), // oldBlockId
            bytes32(uint256(1)), // newBlockId
            block.timestamp - 1, // newTimestamp
            bytes32(0), // oldLatestClosedOrder
            orderId, // newLatestClosedOrder
            bytes32(0), // oldStateHash
            bytes32(uint256(1)), // newStateHash
            closedOrders // closedOrders
        );

        bytes memory proof = new bytes(0);

        console.logBytes32(untron.blockId());
        console.logBytes32(untron.latestClosedOrder());
        console.logBytes32(untron.stateHash());

        untron.closeOrders(proof, publicValues);
        vm.stopPrank();

        console.logBytes32(untron.blockId());
        console.logBytes32(untron.latestClosedOrder());
        console.logBytes32(untron.stateHash());

        // Check state updates
        assertEq(untron.blockId(), bytes32(uint256(1)));
        assertEq(untron.latestClosedOrder(), orderId);
        assertEq(untron.stateHash(), bytes32(uint256(1)));
    }

    function testChangeRateLimit() public {
        vm.prank(admin);
        untron.changeRateLimit(20, 48 hours);

        // We can't directly access the internal variables, so we'll test the effect indirectly
        // by trying to create multiple orders and expecting it to fail after the 20th
        vm.startPrank(provider);
        usdt.mint(provider, 2000e6);
        usdt.approve(address(untron), 2000e6);

        address[] memory receivers = new address[](20);
        for (uint256 i = 0; i < 20; i++) {
            receivers[i] = address(uint160(100 + i));
        }

        untron.setProvider(2000e6, 1e6, 100e6, 10e6, receivers);
        vm.stopPrank();

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

        for (uint256 i = 0; i < 20; i++) {
            untron.createOrder(provider, receivers[i], 100e6, 1e6, transfer);
        }

        vm.expectRevert();
        untron.createOrder(provider, address(200), 100e6, 1e6, transfer);

        vm.stopPrank();
    }
}
