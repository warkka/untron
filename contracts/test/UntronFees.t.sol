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

contract UntronFeesTest is Test {
    UntronCore untronFeesImplementation;
    UntronCore untronFees;
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
        untronFeesImplementation = new UntronCore();
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
            bytes32(0) // vkey
        );

        // Deploy the proxy, pointing to the implementation and passing the init data
        ERC1967Proxy proxy = new ERC1967Proxy(address(untronFeesImplementation), initData);
        untronFees = UntronCore(address(proxy));

        vm.stopPrank();
    }

    function test_setUp() public view {
        // Check role
        assertEq(untronFees.owner(), admin);
    }

    function test_setUntronFeesVariables_SetVariables() public {
        vm.startPrank(admin);

        uint256 relayerFee = 100;
        uint256 feePoint = 100;

        untronFees.setFeesVariables(relayerFee, feePoint);

        assertEq(untronFees.relayerFee(), relayerFee);
        assertEq(untronFees.feePoint(), feePoint);

        vm.stopPrank();
    }

    function test_setUntronFeesVariables_RevertIf_NotUpgraderRole() public {
        uint256 relayerFee = 100;
        uint256 feePoint = 100;

        vm.expectRevert();
        untronFees.setFeesVariables(relayerFee, feePoint);
    }
}
