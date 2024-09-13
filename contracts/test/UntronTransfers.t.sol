// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/UntronCore.sol";
import "../src/UntronTransfers.sol";
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
    UntronTransfers untronTransfersImplementation;
    UntronTransfers untronTransfers;
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
            UntronCore.initialize.selector, address(spokePool), address(usdt), address(aggregationRouter)
        );

        // Deploy the proxy, pointing to the implementation and passing the init data
        ERC1967Proxy proxy = new ERC1967Proxy(address(untronTransfersImplementation), initData);
        untronTransfers = UntronTransfers(address(proxy));
        untronTransfers.grantRole(untronTransfers.DEFAULT_ADMIN_ROLE(), admin);

        vm.stopPrank();
    }

    function test_setUp() public view {
        assertEq(untronTransfers.spokePool(), address(spokePool));
        assertEq(untronTransfers.usdt(), address(usdt));
        assertEq(untronTransfers.swapper(), address(aggregationRouter));

        // Check role
        assertEq(untronTransfers.hasRole(untronTransfers.UPGRADER_ROLE(), admin), true);
    }

    function test_withdrawLeftovers_WithdrawLeftovers() public {
        vm.startPrank(admin);

        untronTransfers.withdrawLeftovers();

        // Since leftovers is 0 and is internal we can only check that there is no revert
        // and that the USDT balance of the contract and the admin is 0 (ie nothing was transferred)
        assertEq(usdt.balanceOf(address(untronTransfers)), 0);
        assertEq(usdt.balanceOf(admin), 0);

        vm.stopPrank();
    }

    function test_withdrawLeftovers_RevertIf_NoDefaultAdminRole() public {
        vm.expectRevert();
        untronTransfers.withdrawLeftovers();
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
