// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./IUntronTransfers.sol";
import "./IUntronState.sol";
import "./IUntronZK.sol";
import "./IUntronFees.sol";

/// @title Interface for the UntronCore contract
/// @author Ultrasound Labs
/// @notice This interface defines the functions and structs used in the UntronCore contract.
interface IUntronCore is IUntronTransfers, IUntronFees, IUntronZK, IUntronState {
    /// @notice Struct representing a Tron->L2 order in the Untron protocol
    struct Order {
        // the tip of the action chain before this order was created
        bytes32 parent;
        // the timestamp of the order
        uint256 timestamp;
        // the creator of the order (will send USDT Tron)
        address creator;
        // the liquidity provider of the order (will receive USDT Tron in exchange for their USDT L2)
        address provider;
        // the provider's receiver of the order (will receive USDT Tron)
        address receiver;
        // the size of the order (in USDT Tron)
        uint256 size;
        // the rate of the order (in USDT L2 per 1 USDT Tron)
        // divided by 1e6 (see "bp" in UntronFees.sol)
        uint256 rate;
        // the minimum deposit in USDT Tron
        uint256 minDeposit;
        // boolean indicating if the order is fulfilled. If it is then the order creator is the fulfiller.
        // if not, then it is simply the order creator.
        bool isFulfilled;
        // the transfer details for the order.
        // It can be as simple as a direct USDT L2 (zksync) transfer to the recipient,
        // or it can be a more complex transfer such as a 1inch swap of USDT L2 (zksync) to the other coin,
        // or/and a cross-chain transfer of the coin to the other network through Across bridge.
        Transfer transfer;
    }

    /// @notice Struct representing the liquidity provider in the Untron protocol
    struct Provider {
        // provider's total liquidity in USDT L2
        uint256 liquidity;
        // provider's current rate in USDT L2 per 1 USDT Tron
        uint256 rate;
        // minimum order size in USDT Tron
        uint256 minOrderSize;
        // minimum deposit in USDT Tron
        uint256 minDeposit;
        // provider's Tron addresses to receive the USDT Tron from the order creators
        address[] receivers;
    }

    /// @notice Struct representing the inflow of USDT Tron to the Untron protocol.
    /// @dev This struct is created within the ZK part of the protocol.
    ///      It represents the amount of USDT Tron that the order creator has sent to the receiver address
    ///      specified in the order with specified ID.
    ///      As the ZK program is the one scanning all USDT transfers in Tron blockchain,
    ///      it is able to find all the transfers to active receivers.
    ///      Then it aggregates them into Inflow structs and sends to the onchain part of the protocol.
    ///      Important note: ZK program doesn't accept USDT transfers less than minDeposit (see /program in the repo)
    struct Inflow {
        // the order ID
        bytes32 order;
        // the inflow amount in USDT Tron
        uint256 inflow;
    }

    event OrderCreated(
        bytes32 orderId,
        uint256 timestamp,
        address creator,
        address indexed provider,
        address receiver,
        uint256 size,
        uint256 rate,
        uint256 minDeposit
    );
    event OrderChanged(bytes32 orderId);
    event OrderStopped(bytes32 orderId);
    event ActionChainUpdated(bytes32 orderId, uint256 timestamp, address receiver, uint256 minDeposit);
    event OrderFulfilled(bytes32 indexed orderId, address fulfiller);
    event OrderClosed(bytes32 indexed orderId, address relayer);
    event RelayUpdated(address relayer, bytes32 newBlockId, bytes32 newLatestClosedOrder, bytes32 newStateHash);
    event ProviderUpdated(
        address indexed provider, uint256 liquidity, uint256 rate, uint256 minOrderSize, uint256 minDeposit
    );

    function providers(address provider) external view returns (Provider memory);
    function isReceiverBusy(address receiver) external view returns (bytes32);
    function receiverOwners(address receiver) external view returns (address);
    function orders(bytes32 orderId) external view returns (Order memory);

    /// @notice Updates the UntronCore-related variables
    /// @param _blockId The new block ID of the latest zk proven Tron block
    /// @param _actionChainTip The new action chain tip
    /// @param _latestExecutedAction The new latest performed action from the action chain
    /// @param _stateHash The new hash of the latest state of Untron ZK program
    function setCoreVariables(
        bytes32 _blockId,
        bytes32 _actionChainTip,
        bytes32 _latestExecutedAction,
        bytes32 _stateHash,
        uint256 _maxOrderSize
    ) external;

    /// @notice The order creation function
    /// @param provider The address of the liquidity provider owning the Tron receiver address.
    /// @param receiver The address of the Tron receiver address
    ///                that's used to perform a USDT transfer on Tron.
    /// @param size The maximum size of the order in USDT L2.
    /// @param rate The "USDT L2 per 1 USDT Tron" rate of the order.
    /// @param transfer The transfer details.
    ///                 They'll be used in the fulfill or closeOrders functions to send respective
    ///                 USDT L2 to the order creator or convert them into whatever the order creator wants to receive
    ///                 for their USDT Tron.
    function createOrder(address provider, address receiver, uint256 size, uint256 rate, Transfer calldata transfer)
        external;
}
