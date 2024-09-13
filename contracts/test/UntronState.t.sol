// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/core/UntronCore.sol";
import "../src/core/UntronState.sol";
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

contract UntronStateTest is Test {
    UntronState untronStateImplementation;
    UntronState untronState;
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
        untronStateImplementation = new UntronCore();
        // Prepare the initialization data
        bytes memory initData = abi.encodeWithSelector(
            UntronCore.initialize.selector, address(spokePool), address(usdt), address(aggregationRouter)
        );

        // Deploy the proxy, pointing to the implementation and passing the init data
        ERC1967Proxy proxy = new ERC1967Proxy(address(untronStateImplementation), initData);
        untronState = UntronState(address(proxy));
        untronState.grantRole(untronState.UPGRADER_ROLE(), admin);

        vm.stopPrank();
    }

    function test_setUp() public view {
        // Check role
        assertEq(untronState.hasRole(untronState.UPGRADER_ROLE(), admin), true);
    }

    function test_changeRateLimit_SetRateLimit() public {
        vm.startPrank(admin);

        uint256 rateLimit = 10;
        uint256 rateLimitPeriod = 24 hours;

        untronState.changeRateLimit(rateLimit, rateLimitPeriod);

        assertEq(untronState.maxSponsorships(), rateLimit);
        assertEq(untronState.per(), rateLimitPeriod);

        vm.stopPrank();
    }

    function test_changeRateLimit_RevertIf_NotUpgraderRole() public {
        uint256 rateLimit = 10;
        uint256 rateLimitDuration = 24 hours;

        vm.expectRevert();
        untronState.changeRateLimit(rateLimit, rateLimitDuration);
    }
}
