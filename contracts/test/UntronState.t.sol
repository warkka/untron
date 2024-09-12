// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/UntronCore.sol";
import "../src/UntronState.sol";
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
        assertEq(untronState.spokePool(), address(spokePool));
        assertEq(untronState.usdt(), address(usdt));
        assertEq(untronState.swapper(), address(aggregationRouter));

        // Check role
        assertEq(untronState.hasRole(untronState.UPGRADER_ROLE(), admin), true);
    }

    function test_setUntronCoreVariables_SetVariables() public {
        vm.startPrank(admin);

        bytes32 blockId = bytes32(uint256(1));
        bytes32 actionChainTip = bytes32(uint256(2));
        bytes32 latestPerformedAction = bytes32(uint256(3));
        bytes32 stateHash = bytes32(uint256(4));
        uint256 maxOrderSize = 100;

        untronState.setUntronCoreVariables(blockId, actionChainTip, latestPerformedAction, stateHash, maxOrderSize);

        assertEq(untronState.blockId(), blockId);
        assertEq(untronState.actionChainTip(), actionChainTip);
        assertEq(untronState.latestPerformedAction(), latestPerformedAction);
        assertEq(untronState.stateHash(), stateHash);
        assertEq(untronState.maxOrderSize(), maxOrderSize);

        vm.stopPrank();
    }

    function test_setUntronCoreVariables_RevertIf_NotUpgraderRole() public {
        bytes32 blockId = bytes32(uint256(1));
        bytes32 actionChainTip = bytes32(uint256(2));
        bytes32 latestPerformedAction = bytes32(uint256(3));
        bytes32 stateHash = bytes32(uint256(4));
        uint256 maxOrderSize = 100;

        vm.expectRevert();
        untronState.setUntronCoreVariables(blockId, actionChainTip, latestPerformedAction, stateHash, maxOrderSize);
    }

    function test_setUntronZKVariables_SetVariables() public {
        vm.startPrank(admin);

        address verifier = address(sp1Verifier);
        bytes32 vkey = bytes32(uint256(1));

        untronState.setUntronZKVariables(verifier, vkey);

        assertEq(untronState.verifier(), verifier);
        assertEq(untronState.vkey(), vkey);

        vm.stopPrank();
    }

    function test_setUntronZKVariables_RevertIf_NotUpgraderRole() public {
        address verifier = address(sp1Verifier);
        bytes32 vkey = bytes32(uint256(1));

        vm.expectRevert();
        untronState.setUntronZKVariables(verifier, vkey);
    }

    function test_setUntronFeesVariables_SetVariables() public {
        vm.startPrank(admin);

        uint256 relayerFee = 100;
        uint256 feePoint = 100;

        untronState.setUntronFeesVariables(relayerFee, feePoint);

        assertEq(untronState.relayerFee(), relayerFee);
        assertEq(untronState.feePoint(), feePoint);

        vm.stopPrank();
    }

    function test_setUntronFeesVariables_RevertIf_NotUpgraderRole() public {
        uint256 relayerFee = 100;
        uint256 feePoint = 100;

        vm.expectRevert();
        untronState.setUntronFeesVariables(relayerFee, feePoint);
    }

    function test_setUntronTransfersVariables_SetVariables() public {
        vm.startPrank(admin);

        address usdtAddress = address(usdt);
        address spokePoolAddress = address(spokePool);
        address aggregationRouterAddress = address(aggregationRouter);

        untronState.setUntronTransfersVariables(usdtAddress, spokePoolAddress, aggregationRouterAddress);

        assertEq(untronState.usdt(), usdtAddress);
        assertEq(untronState.spokePool(), spokePoolAddress);
        assertEq(untronState.swapper(), aggregationRouterAddress);

        vm.stopPrank();
    }

    function test_setUntronTransfersVariables_RevertIf_NotUpgraderRole() public {
        address usdtAddress = address(usdt);
        address spokePoolAddress = address(spokePool);
        address aggregationRouterAddress = address(aggregationRouter);

        vm.expectRevert();
        untronState.setUntronTransfersVariables(usdtAddress, spokePoolAddress, aggregationRouterAddress);
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
