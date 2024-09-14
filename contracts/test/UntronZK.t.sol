// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/UntronV1.sol";
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

contract UntronZKTest is Test {
    UntronV1 untronZKImplementation;
    UntronV1 untronZK;
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
        untronZKImplementation = new UntronV1();
        // Prepare the initialization data
        bytes memory initData = abi.encodeWithSelector(
            UntronV1.initialize.selector,
            bytes32(0), // blockId
            bytes32(0), // stateHash
            1000e6, // maxOrderSize
            address(spokePool),
            address(usdt),
            address(aggregationRouter),
            100, // relayerFee
            10000, // feePoint
            address(sp1Verifier),
            bytes32(0), // vkey
            10, // rate
            24 hours // per
        );

        // Deploy the proxy, pointing to the implementation and passing the init data
        ERC1967Proxy proxy = new ERC1967Proxy(address(untronZKImplementation), initData);
        untronZK = UntronV1(address(proxy));
        untronZK.grantRole(untronZK.UPGRADER_ROLE(), admin);

        vm.stopPrank();
    }

    function test_setUp() public view {
        // Check role
        assertEq(untronZK.hasRole(untronZK.UPGRADER_ROLE(), admin), true);
    }

    function test_setUntronZKVariables_SetVariables() public {
        vm.startPrank(admin);

        address verifier = address(sp1Verifier);
        bytes32 vkey = bytes32(uint256(1));

        untronZK.setZKVariables(verifier, vkey);

        assertEq(untronZK.verifier(), verifier);
        assertEq(untronZK.vkey(), vkey);

        vm.stopPrank();
    }

    function test_setUntronZKVariables_RevertIf_NotUpgraderRole() public {
        address verifier = address(sp1Verifier);
        bytes32 vkey = bytes32(uint256(1));

        vm.expectRevert();
        untronZK.setZKVariables(verifier, vkey);
    }
}
