// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./interfaces/V3SpokePoolInterface.sol";
import "./interfaces/ISender.sol";

contract Sender is ISender {
    // https://docs.across.to/reference/contract-addresses/zksync-chain-id-324
    V3SpokePoolInterface spokePool = V3SpokePoolInterface(0xE0B015E54d54fc84a6cB9B666099c46adE9335FF);
    IERC20 constant usdt = IERC20(0x493257fD37EDB34451f62EDf8D2a0C418852bA4C); // bridged USDT @ zksync era

    constructor() {
        usdt.approve(address(spokePool), type(uint256).max);
    }

    function send(uint64 amount, bytes calldata transferData) external {
        (uint256 magic, bytes memory data) = abi.decode(transferData, (uint256, bytes));
        require(magic == 0); // magic is used for backwards compatibility

        (address recipient, uint256 totalRelayFee, uint256 chainId) = abi.decode(data, (address, uint256, uint256));

        if (chainId == 324) {
            // zksync era
            usdt.transferFrom(msg.sender, recipient, uint256(amount));
            return;
        }

        usdt.transferFrom(msg.sender, address(this), uint256(amount));

        spokePool.depositV3(
            msg.sender,
            recipient,
            address(usdt),
            address(0),
            uint256(amount),
            uint256(amount) - totalRelayFee,
            chainId,
            address(0),
            uint32(block.timestamp - 36),
            uint32(block.timestamp + 18000),
            0,
            ""
        );
    }
}
