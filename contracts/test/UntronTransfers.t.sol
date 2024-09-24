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

contract UntronTransfersTest is Test {
    UntronCore untronTransfersImplementation;
    UntronCore untronTransfers;
    MockSpokePool spokePool;
    MockAggregationRouter aggregationRouter;
    SP1MockVerifier sp1Verifier;
    MockUSDT usdt;

    address admin = address(1);

    constructor() {
        vm.warp(1725527575); // the time i did this test at
    }

    function setUp() public {
        vm.startPrank(admin);

        spokePool = new MockSpokePool();
        aggregationRouter = new MockAggregationRouter();
        sp1Verifier = new SP1MockVerifier();
        usdt = new MockUSDT();

        // Use UntronCore since UntronFees is abstract
        untronTransfersImplementation = new UntronCore();
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
            address(sp1Verifier),
            bytes32(0) // vkey
        );

        // Deploy the proxy, pointing to the implementation and passing the init data
        ERC1967Proxy proxy = new ERC1967Proxy(address(untronTransfersImplementation), initData);
        untronTransfers = UntronCore(address(proxy));

        vm.stopPrank();
    }

    function test_setUp() public view {
        assertEq(untronTransfers.spokePool(), address(spokePool));
        assertEq(untronTransfers.usdt(), address(usdt));
        assertEq(untronTransfers.swapper(), address(aggregationRouter));

        // Check role
        assertEq(untronTransfers.owner(), admin);
    }

    function test_setUntronTransfersVariables_SetVariables() public {
        vm.startPrank(admin);

        address usdtAddress = address(usdt);
        address spokePoolAddress = address(spokePool);
        address aggregationRouterAddress = address(aggregationRouter);

        untronTransfers.setTransfersVariables(usdtAddress, spokePoolAddress, aggregationRouterAddress);

        assertEq(untronTransfers.usdt(), usdtAddress);
        assertEq(untronTransfers.spokePool(), spokePoolAddress);
        assertEq(untronTransfers.swapper(), aggregationRouterAddress);

        vm.stopPrank();
    }

    function test_setUntronTransfersVariables_RevertIf_NotUpgraderRole() public {
        address usdtAddress = address(usdt);
        address spokePoolAddress = address(spokePool);
        address aggregationRouterAddress = address(aggregationRouter);

        vm.expectRevert();
        untronTransfers.setTransfersVariables(usdtAddress, spokePoolAddress, aggregationRouterAddress);
    }
}
