// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./core/IUntronCore.sol";

interface IUntronV1 is IUntronCore {
    /// @notice Estimates the collateral required to create an order.
    /// @param provider The address of the provider.
    /// @param receiver The address of the receiver.
    /// @param size The size of the order.
    /// @param rate The rate of the order.
    /// @param transfer The transfer details.
    /// @return uint256 The collateral required to create the order.
    /// @dev Every order in the Untron protocol incurs indirect expenses for liquidity providers.
    ///      Specifically, every order temporarily locks one of provider's receivers for at most 5 minutes
    ///      and some of their liquidity, depending on the order size. In cases where the order wasn't performed
    ///      or closed before expiration, the liquidity can be withheld to up to 1-3 hours - the ZK proof generation time.
    ///      Therefore, every unperformed and unclosed order incurs some opportunity cost for the provider.
    ///      This function should closely estimate the collateral required to cover the opportunity cost of creating an order.
    ///      In case the order wasn't closed before expiration, the provider will be able to take the creator's collateral.
    ///      This way, we make DDoS attacks on Untron and its providers economically unfeasible.
    ///      In Untron V1, the collateral estimation is based on the percentage from the order size and thus is not very accurate.
    ///      In the next versions of Untron, we'll make the collateral estimation more accurate
    ///      and based on the numbers estimated from onchain data.
    function estimateCollateral(
        address provider,
        address receiver,
        uint256 size,
        uint256 rate,
        Transfer memory transfer
    ) external view returns (uint256);
}
