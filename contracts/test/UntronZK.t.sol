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

contract UntronZKTest is Test {
    UntronZK untronZKImplementation;
    UntronZK untronZK;
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
        untronZKImplementation = new UntronCore();
        // Prepare the initialization data
        bytes memory initData = abi.encodeWithSelector(
            UntronCore.initialize.selector, address(spokePool), address(usdt), address(aggregationRouter)
        );

        // Deploy the proxy, pointing to the implementation and passing the init data
        ERC1967Proxy proxy = new ERC1967Proxy(address(untronZKImplementation), initData);
        untronZK = UntronZK(address(proxy));
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
