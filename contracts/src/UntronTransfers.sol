// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./interfaces/external/V3SpokePoolInterface.sol";
import "./interfaces/external/IAggregationRouterV6.sol";
import "./interfaces/IUntronTransfers.sol";
import "./UntronState.sol";
import "./UntronTools.sol";

abstract contract UntronTransfers is IUntronTransfers, UntronTools, Initializable, UntronState {
    function __UntronTransfers_init(address _spokePool, address _usdt, address _swapper) internal onlyInitializing {
        __UntronState_init();

        spokePool = _spokePool;
        usdt = _usdt;
        swapper = _swapper;
    }

    function swapUSDT(Transfer memory transfer, uint256 amount) internal returns (uint256 output) {
        IERC20(usdt).approve(swapper, amount);

        IAggregationRouterV6.SwapDescription memory desc = IAggregationRouterV6.SwapDescription({
            srcToken: IERC20(usdt),
            dstToken: IERC20(transfer.outToken),
            srcReceiver: payable(address(this)),
            dstReceiver: payable(address(this)),
            amount: amount,
            minReturnAmount: transfer.minOutputPerUSDT * amount / 1e6,
            flags: 0
        });

        (address executor, bytes memory data) = abi.decode(transfer.swapData, (address, bytes));

        (output,) = IAggregationRouterV6(swapper).swap(
            executor, // Now we're passing the executor address
            desc,
            "", // We're not using the permit functionality
            data // This should be obtained from the 1inch API
        );
    }

    uint256 internal leftovers;

    function smartTransfer(Transfer memory transfer, uint256 amount) internal {
        if (transfer.doSwap) {
            uint256 output = swapUSDT(transfer, amount);
            if (transfer.fixedOutput) {
                amount = transfer.minOutputPerUSDT * amount / 1e6;
                leftovers += output - amount;
            } else {
                amount = output;
            }
        }

        if (transfer.chainId == chainId()) {
            internalTransfer(transfer.recipient, amount);
        } else {
            V3SpokePoolInterface(spokePool).depositV3(
                msg.sender,
                transfer.recipient,
                address(usdt),
                address(0),
                amount,
                amount - transfer.acrossFee,
                transfer.chainId,
                address(0),
                uint32(block.timestamp - 36),
                uint32(block.timestamp + 1800),
                0,
                ""
            );
        }
    }

    function internalTransfer(address to, uint256 amount) internal {
        require(IERC20(usdt).transfer(to, amount));
    }

    function internalTransferFrom(address from, uint256 amount) internal {
        require(IERC20(usdt).transferFrom(from, address(this), amount));
    }
}
