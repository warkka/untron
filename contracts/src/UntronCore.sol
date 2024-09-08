// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

// import "forge-std/console.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "./interfaces/IUntronCore.sol";
import "./UntronTransfers.sol";
import "./UntronTools.sol";
import "./UntronFees.sol";
import "./UntronZK.sol";

/// @title Main smart contract for Untron
/// @author Ultrasound Labs
/// @notice This contract is the main entry point for implementation of the Untron protocol.
///         It's designed to be fully upgradeable and modular, with each module being a separate contract.
contract UntronCore is Initializable, UntronTransfers, UntronFees, UntronZK, IUntronCore, UUPSUpgradeable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract with the provided parameters.
    /// @param _spokePool The address of the Across bridge's SpokePool contract.
    /// @param _usdt The address of the USDT token.
    /// @param _swapper The address of the contract implementing swap logic.
    /// @dev This function grants the DEFAULT_ADMIN_ROLE and UPGRADER_ROLE to the msg.sender.
    ///      Upgrader role allows to upgrade the contract and dynamic values (see UntronState)
    function initialize(address _spokePool, address _usdt, address _swapper) public initializer {
        // initialize Access Control
        __AccessControl_init();
        // initialize UUPS
        __UUPSUpgradeable_init();

        // initialize UntronState
        __UntronState_init();

        // initialize UntronTransfers
        __UntronTransfers_init(_spokePool, _usdt, _swapper);

        // initialize UntronFees
        __UntronFees_init(100, 10000); // 0.01% relayer fee, 0.01 USDT fee point

        // initialize UntronZK
        __UntronZK_init();

        // grant all necessary roles to msg.sender
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);
        _grantRole(UNLIMITED_CREATOR_ROLE, msg.sender);
    }

    /// @notice Mapping to store provider details.
    mapping(address => Provider) private _providers;
    /// @notice Mapping to store whether a receiver is busy with an order.
    mapping(address => bytes32) private _isReceiverBusy;
    /// @notice Mapping to store the owner (provider) of a receiver.
    mapping(address => address) private _receiverOwners;
    /// @notice Mapping to store order details by order ID.
    mapping(bytes32 => Order) private _orders;

    function providers(address provider) external view returns (Provider memory) {
        return _providers[provider];
    }

    function isReceiverBusy(address receiver) external view returns (bytes32) {
        return _isReceiverBusy[receiver];
    }

    function receiverOwners(address receiver) external view returns (address) {
        return _receiverOwners[receiver];
    }

    function orders(bytes32 orderId) external view returns (Order memory) {
        return _orders[orderId];
    }

    /// @notice Updates the order chain and returns the new order ID.
    /// @param receiver The address of the receiver.
    /// @param minDeposit The minimum deposit amount.
    /// @return orderId The new order ID.
    function updateOrderChain(address receiver, uint256 minDeposit) internal returns (bytes32 orderId) {
        // order ID is a chained hash of the previous latest order ID, the current block timestamp,
        // the receiver address, and the minimum deposit amount, ABI-encoded and SHA256 hashed.
        // Tron-format timestamp is used because we use the order chain in the ZK circuit which accepts Tron block data.
        // ABI: (bytes32, uint256, address, uint256)
        uint256 tronTimestamp = unixToTron(block.timestamp);
        orderId = sha256(abi.encode(latestOrder, tronTimestamp, receiver, minDeposit));
        // latestOrder stores the latest order ID, that is, the tip of the order chain.
        latestOrder = orderId;
    }

    /// @notice Creates an order with no checks.
    /// @param creator The address of the creator
    ///                who is authorized to change and stop this order
    /// @param provider The address of the liquidity provider owning the Tron receiver address.
    /// @param receiver The address of the Tron receiver address
    ///                 that's used to perform a USDT transfer on Tron.
    /// @param size The maximum size of the order in USDT L2.
    /// @param rate The "USDT L2 per 1 USDT Tron" rate of the order.
    /// @param transfer The transfer details.
    ///                 They'll be used in the fulfill or closeOrders functions to send respective
    ///                 USDT L2 to the user or convert them into whatever the user wants to receive
    ///                 for their USDT Tron.
    /// @dev This function must only be called in the createOrder and createOrderUnlimited functions.
    function _createOrder(
        address creator,
        address provider,
        address receiver,
        uint256 size,
        uint256 rate,
        Transfer calldata transfer
    ) internal {
        // amount is the amount of USDT L2 that will be taken from the provider
        // based on the order size (which is in USDT Tron) and provider's rate
        (uint256 amount,) = conversion(size, rate, 0, false);
        uint256 providerMinDeposit = _providers[provider].minDeposit;

        require(_isReceiverBusy[receiver] == bytes32(0), "Receiver is busy");
        require(_receiverOwners[receiver] == provider, "Receiver is not owned by provider");
        require(_providers[provider].liquidity >= amount, "Provider does not have enough liquidity");
        require(rate == _providers[provider].rate, "Rate does not match provider's rate");
        require(providerMinDeposit <= size, "Min deposit is greater than size");
        require(size <= maxOrderSize, "Size is greater than max order size");

        // subtract the amount from the provider's liquidity
        _providers[provider].liquidity -= amount;

        // get the previous order ID
        bytes32 prevOrder = latestOrder;
        // create the order ID and update the order chain
        bytes32 orderId = updateOrderChain(receiver, providerMinDeposit);
        // set the receiver as busy to prevent double orders
        _isReceiverBusy[receiver] = orderId;
        uint256 timestamp = unixToTron(block.timestamp);
        // store the order details in storage
        _orders[orderId] = Order({
            prevOrder: prevOrder,
            timestamp: timestamp,
            creator: creator,
            provider: provider,
            receiver: receiver,
            size: size,
            rate: rate,
            minDeposit: providerMinDeposit,
            transfer: transfer
        });

        // Emit OrderCreated event
        emit OrderCreated(orderId, timestamp, creator, provider, receiver, size, rate, providerMinDeposit);
    }

    /// @notice Rate-limited order creation function
    /// @param provider The address of the liquidity provider owning the Tron receiver address.
    /// @param receiver The address of the Tron receiver address
    ///                that's used to perform a USDT transfer on Tron.
    /// @param size The maximum size of the order in USDT L2.
    /// @param rate The "USDT L2 per 1 USDT Tron" rate of the order.
    /// @param transfer The transfer details.
    ///                 They'll be used in the fulfill or closeOrders functions to send respective
    ///                 USDT L2 to the user or convert them into whatever the user wants to receive
    ///                 for their USDT Tron.
    /// @dev The function is rate-limited based on limits specified in UntronState.
    function createOrder(address provider, address receiver, uint256 size, uint256 rate, Transfer calldata transfer)
        external
        ratePer(maxSponsorships, per, true)
    {
        // proceed with order creation (rate limiting is done in the modifier)
        _createOrder(msg.sender, provider, receiver, size, rate, transfer);
    }

    /// @notice Access Control role for unlimited order creation.
    /// @dev This role will be delegated to Untron team for integrations with projects not on ZKsync Era
    ///      so they could create orders on behalf of the protocol without creating accounts on Era.
    ///      We expect this design to be temporary and to be replaced with a more flexible and secure
    ///      design in the future.
    bytes32 public constant UNLIMITED_CREATOR_ROLE = keccak256("UNLIMITED_CREATOR_ROLE");

    /// @notice Unlimited order creation function
    /// @param provider The address of the liquidity provider owning the Tron receiver address.
    /// @param receiver The address of the Tron receiver address
    ///                that's used to perform a USDT transfer on Tron.
    /// @param size The maximum size of the order in USDT L2.
    /// @param rate The "USDT L2 per 1 USDT Tron" rate of the order.
    /// @param transfer The transfer details.
    ///                 They'll be used in the fulfill or closeOrders functions to send respective
    ///                 USDT L2 to the user or convert them into to whatever the user wants to receive
    ///                 for their USDT Tron.
    function createOrderUnlimited(
        address provider,
        address receiver,
        uint256 size,
        uint256 rate,
        Transfer calldata transfer
    ) external onlyRole(UNLIMITED_CREATOR_ROLE) {
        // proceed with order creation (no rate limiting because the initiator is trusted)
        _createOrder(msg.sender, provider, receiver, size, rate, transfer);
    }

    /// @notice Changes the transfer details of an order.
    /// @param orderId The ID of the order to change.
    /// @param transfer The new transfer details.
    /// @dev The transfer details can only be changed before the order is fulfilled.
    function changeOrder(bytes32 orderId, Transfer calldata transfer) external {
        require(_orders[orderId].creator == msg.sender, "Only creator can change the order");

        // change the transfer details
        _orders[orderId].transfer = transfer;

        // Emit OrderChanged event
        emit OrderChanged(orderId);
    }

    /// @notice Stops the order and returns the remaining liquidity to the provider.
    /// @param orderId The ID of the order to stop.
    /// @dev The order can only be stopped before it's fulfilled.
    ///      Closing and stopping the order are different things.
    ///      Closing means that provider's funds are unlocked to either the user or the provider
    ///      as the order completed its listening cycle.
    ///      Stopping means that the order no longer needs listening for new USDT Tron transfers
    ///      and won't be fulfilled.
    function stopOrder(bytes32 orderId) external {
        require(_orders[orderId].creator == msg.sender, "Only creator can stop the order");

        // update the order chain with stop notifier
        updateOrderChain(_orders[orderId].receiver, 0);
        // set the receiver as not busy because the order is stopped
        _isReceiverBusy[_orders[orderId].receiver] = bytes32(0);

        // return the liquidity back to the provider
        _providers[_orders[orderId].provider].liquidity += _orders[orderId].size;

        // delete the order because it won't be fulfilled/closed
        // (stopOrder assumes that the user sent nothing)
        delete _orders[orderId];

        // Emit OrderStopped event
        emit OrderStopped(orderId);
    }

    function _getAmountAndFee(Order memory order) internal view returns (uint256 amount, uint256 fee) {
        // calculate the fulfiller fee given the order details
        fee = calculateFee(order.transfer.doSwap, order.transfer.chainId);
        // calculate the amount of USDT L2 that the fulfiller will have to send
        (amount,) = conversion(order.size, order.rate, fee, true);
    }

    function _getActiveOrderByReceiver(address receiver) internal view returns (Order memory) {
        // get the active order ID for the receiver
        bytes32 activeOrderId = _isReceiverBusy[receiver];
        // get the order details
        return _orders[activeOrderId];
    }

    /// @notice Helper function that calculates the fulfiller's total expense and income given the receivers.
    /// @param _receivers The addresses of the receivers.
    /// @return totalExpense The total expense in USDT L2.
    /// @return totalProfit The total profit in USDT L2.
    function calculateFulfillerTotal(address[] calldata _receivers)
        external
        view
        returns (uint256 totalExpense, uint256 totalProfit)
    {
        // iterate over the receivers
        for (uint256 i = 0; i < _receivers.length; i++) {
            Order memory order = _getActiveOrderByReceiver(_receivers[i]);
            (uint256 amount, uint256 fulfillerFee) = _getAmountAndFee(order);

            // add the amount to the total expense and the fee to the total profit
            totalExpense += amount;
            totalProfit += fulfillerFee;
        }
    }

    /// @notice Fulfills the orders by sending their ask in advance.
    /// @param _receivers The addresses of the receivers.
    /// @param total The total amount of USDT L2 to transfer.
    /// @dev Fulfillment exists because ZK proofs that actually *close* the orders
    ///      are published every 60-90 minutes. This means that provider's funds
    ///      will only be unlocked to them or to order creators with this delay.
    ///      However, we want the users to receive the funds ASAP.
    ///      Fulfillers send users' ask in advance when they see that their USDT
    ///      transfer happened on Tron blockchain, but wasn't ZK proven yet.
    ///      After the transfer is ZK proven, they'll receive the full amount of
    ///      USDT L2.
    ///      Fulfillers take the fee for the service, which depends on complexity of the transfer
    ///      (if it requires a swap or not, what's the chain of the transfer, etc).
    function fulfill(address[] calldata _receivers, uint256 total) external {
        // take the declared amount of USDT L2 from the fulfiller
        internalTransferFrom(msg.sender, total);
        // this variable will be used to calculate how much the contract sent to the users.
        // this number must be equal to "total" to prevent the fulfiller from stealing the funds in the contract.
        uint256 expectedTotal;

        // iterate over the receivers
        for (uint256 i = 0; i < _receivers.length; i++) {
            // get the order ID
            bytes32 activeOrderId = _isReceiverBusy[_receivers[i]];

            // get the active order ID for the receiver
            Order memory order = _orders[activeOrderId];
            
            (uint256 amount,) = _getAmountAndFee(order);

            // account for the spent amount in our accounting variable
            expectedTotal += amount;

            // perform the transfer
            smartTransfer(order.transfer, amount);

            // update the order details

            // to prevent from modifying the order after it's fulfilled
            _orders[activeOrderId].creator = msg.sender;
            // to make fulfiller receive provider's USDT L2 after the ZK proof is published
            _orders[activeOrderId].transfer.recipient = msg.sender;
            // fulfiller will always receive provider's USDT L2 on the contract host chain (ZKsync Era),
            // as opposed to user's transfer that could be on any chain
            _orders[activeOrderId].transfer.chainId = chainId();
            // fulfilled orders don't need swaps, because the fulfillers will always receive USDT L2 on the host chain.
            _orders[activeOrderId].transfer.doSwap = false;
            // make the receiver not busy anymore
            delete _isReceiverBusy[_receivers[i]];

            // Emit OrderFulfilled event
            emit OrderFulfilled(activeOrderId, msg.sender);
        }

        // check that the total amount of USDT L2 sent is less or equal to the declared amount
        require(total >= expectedTotal, "Total does not match");

        // refund the fulfiller for the USDT L2 that was sent in excess
        if (expectedTotal < total) {
            internalTransfer(msg.sender, total - expectedTotal);
        }
    }

    /// @notice The timestamp of the last relayer activity.
    /// @dev Used to make closing orders permissionless in case all relayers are down for more than 3 hours.
    uint256 public lastRelayerActivity;

    /// @notice The role for the relayers.
    /// @dev Relayer is a role that is responsible for closing the orders.
    ///      They generate and publish ZK proofs for Tron blockchain and its contents, in exchange for a fee (in percents; see relayerFee in UntronState).
    ///      If all relayers are down for more than 3 hours, relaying becomes permissionless (see lastRelayerActivity).
    bytes32 public constant RELAYER_ROLE = keccak256("RELAYER_ROLE");

    /// @notice Closes the orders and sends the funds to the providers or users, if not fulfilled.
    /// @param proof The ZK proof.
    /// @param publicValues The public values for the proof and order closure.
    function closeOrders(bytes calldata proof, bytes calldata publicValues) external {
        bool isRelayer = hasRole(RELAYER_ROLE, msg.sender);
        // Check if the sender has the relayer role or if all relayers are inactive
        require(
            isRelayer || (block.timestamp - lastRelayerActivity > 3 hours),
            "Caller is not a relayer and relayers are not inactive"
        );

        // Update the last active timestamp for relayers if the caller is a relayer
        if (isRelayer) {
            lastRelayerActivity = block.timestamp;
        }

        // verify the ZK proof with the public values
        // verifying logic is defined in the UntronZK contract.
        // currently it wraps SP1 zkVM verifier.
        verifyProof(proof, publicValues);

        (
            // old block ID must be the latest block ID that was ZK proven (blockId)
            bytes32 oldBlockId,
            // new block ID is the new latest (known) block ID of Tron blockchain
            // all blocks revealed by the ZK proof are finalized in the Tron network
            bytes32 newBlockId,
            // new timestamp is the timestamp of the new latest (known) block of Tron blockchain
            uint256 newTimestamp,
            // "old latest closed order" is the tip of the order chain that was ZK proven last time
            bytes32 oldLatestClosedOrder,
            // "new latest closed order" is the tip of the order chain that is being ZK proven now.
            // it's not necessarily the latest order chain, because the relayer might have
            // ZK proven some old orders when the new ones were created.
            // however, the new closed tip must have been the order chain tip at some point.
            bytes32 newLatestClosedOrder,
            // old state hash is the state print from the previous run of the ZK program.
            bytes32 oldStateHash,
            // new state hash is the state print from the new run of the ZK program.
            bytes32 newStateHash,
            // closed orders are the orders that are being closed in this run of the ZK program.
            Inflow[] memory closedOrders
        ) = abi.decode(publicValues, (bytes32, bytes32, uint256, bytes32, bytes32, bytes32, bytes32, Inflow[]));

        // check that the old block ID is the latest block ID that was ZK proven (blockId)
        require(oldBlockId == blockId);
        // check that the old order chain is the tip of the order chain that was ZK proven last time
        require(oldLatestClosedOrder == latestClosedOrder);
        // require that the timestamp of the latest closed order is greater than or equal
        // to the timestamp of the new latest (known) block of Tron blockchain.
        // this is needed to prevent the relayer from censoring orders until they expire.
        require(_orders[newLatestClosedOrder].timestamp >= newTimestamp);
        // check that the old state hash is equal to the current state hash
        // this is needed to prevent the relayer from modifying the state in the ZK program.
        require(oldStateHash == stateHash);

        // update the block ID, latest closed order and state hash
        blockId = newBlockId;
        latestClosedOrder = newLatestClosedOrder;
        stateHash = newStateHash;

        // this variable is used to calculate the total fee that the relayer will receive
        uint256 totalFee;

        // iterate over the closed orders
        for (uint256 i = 0; i < closedOrders.length; i++) {
            // get the order ID
            bytes32 orderId = closedOrders[i].order;

            // get the minimum inflow amount.
            // minInflow is the minimum number between the inflow amount on Tron and the order size.
            // this is needed so that the user/fulfiller doesn't get more than the order size (locked liquidity).
            uint256 minInflow =
                closedOrders[i].inflow < _orders[orderId].size ? closedOrders[i].inflow : _orders[orderId].size;

            // calculate the amount and fee the user/fulfiller will receive
            (uint256 amount, uint256 fee) = conversion(minInflow, _orders[orderId].rate, 0, true);
            // add the fee to the total fee
            totalFee += fee;

            // remove fixed output flag to make the transfer unrevertable
            // (if the user hadn't changed the transfer details by that time it's their fault tbh)
            _orders[orderId].transfer.fixedOutput = false;

            // perform the transfer
            smartTransfer(_orders[orderId].transfer, amount);

            // emit the OrderClosed event
            emit OrderClosed(orderId, msg.sender);
        }

        // pay the relayer for the service
        internalTransfer(msg.sender, totalFee);

        // emit the RelayUpdated event
        emit RelayUpdated(msg.sender, blockId, latestClosedOrder, stateHash);
    }

    /// @notice Sets the liquidity provider details.
    /// @param liquidity The liquidity of the provider in USDT L2.
    /// @param rate The rate (USDT L2 per 1 USDT Tron) of the provider.
    /// @param minOrderSize The minimum size of the order in USDT Tron.
    /// @param minDeposit The minimum amount the user can transfer to the receiver, in USDT Tron.
    ///                   This is needed for so-called "reverse swaps", when the provider is
    ///                   actually a normal user who wants to swap USDT L2 for USDT Tron,
    ///                   and the user (who creates the orders) is an automated entity,
    ///                   called "sender", that accepts such orders and performs transfers on Tron network.
    ///                   Users doing reverse swaps usually want to receive the entire order size
    ///                   in a single transfer, hence the need for minDeposit.
    ///                   minOrderSize == liquidity * rate signalizes for senders that the provider
    ///                   is a user performing a reverse swap.
    /// @param receivers The provider's Tron addresses that are used to receive USDT Tron.
    ///                  The more receivers the provider has, the more concurrent orders the provider can have.
    function setProvider(
        uint256 liquidity,
        uint256 rate,
        uint256 minOrderSize,
        uint256 minDeposit,
        address[] calldata receivers
    ) external {
        // get provider's current liquidity
        uint256 currentLiquidity = _providers[msg.sender].liquidity;

        // if the provider's current liquidity is less than the new liquidity,
        // the provider needs to deposit the difference
        if (currentLiquidity < liquidity) {
            // transfer the difference from the provider to the contract
            internalTransferFrom(msg.sender, liquidity - currentLiquidity);
        } else if (currentLiquidity > liquidity) {
            // if the provider's current liquidity is greater than the new liquidity,
            // the provider wants to withdraw the difference

            // transfer the difference from the contract to the provider
            internalTransfer(msg.sender, currentLiquidity - liquidity);
        }

        // update the provider's liquidity
        _providers[msg.sender].liquidity = liquidity;

        // update the provider's rate
        _providers[msg.sender].rate = rate;
        // update the provider's minimum order size
        _providers[msg.sender].minOrderSize = minOrderSize;
        // update the provider's minimum deposit
        _providers[msg.sender].minDeposit = minDeposit;
        // update the provider's receivers
        _providers[msg.sender].receivers = receivers;

        // check that the receivers are not already owned by another provider
        for (uint256 i = 0; i < receivers.length; i++) {
            require(_receiverOwners[receivers[i]] == address(0), "Receiver is already owned");
            // set the receiver owner
            _receiverOwners[receivers[i]] = msg.sender;
        }

        // Emit ProviderUpdated event
        emit ProviderUpdated(msg.sender, liquidity, rate, minOrderSize, minDeposit);
    }

    /// @notice Authorizes the upgrade of the contract.
    /// @param newImplementation The address of the new implementation.
    /// @dev This is a UUPS-related function.
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}
}
