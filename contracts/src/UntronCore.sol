// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

// import "forge-std/console.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./interfaces/IUntronCore.sol";
import "./UntronTransfers.sol";
import "./UntronTools.sol";
import "./UntronFees.sol";
import "./UntronZK.sol";

/// @title Core logic for Untron protocol
/// @author Ultrasound Labs
/// @notice This contract contains the main logic of the Untron protocol.
///         It's designed to be fully upgradeable and modular, with each module being a separate contract.
contract UntronCore is Initializable, OwnableUpgradeable, UntronTransfers, UntronFees, UntronZK, IUntronCore {
    uint256 constant ORDER_TTL = 300; // 5 minutes

    /// @notice Initializes the core with the provided parameters.
    /// @param _blockId The ID of the latest ZK proven block of Tron blockchain.
    /// @param _stateHash The state hash of the latest ZK proven block of Tron blockchain.
    /// @param _maxOrderSize The maximum size of the order in USDT L2.
    /// @param _spokePool The address of the Across bridge's SpokePool contract.
    /// @param _usdt The address of the USDT token.
    /// @param _swapper The address of the contract implementing swap logic.
    /// @param _relayerFee The fee charged by the relayer, in percents.
    /// @param _feePoint The basic fee point used to calculate the fee per transfer.
    /// @param _trustedRelayer The address of the trusted relayer (used in case of mock verification)
    /// @param _verifier The address of the ZK proof verifier.
    /// @param _vkey The vkey of the ZK program.
    /// @dev This function grants the DEFAULT_ADMIN_ROLE and UPGRADER_ROLE to the msg.sender.
    ///      Upgrader role allows to upgrade the contract and dynamic values (see UntronState)
    function initialize(
        bytes32 _blockId,
        bytes32 _stateHash,
        uint256 _maxOrderSize,
        address _spokePool,
        address _usdt,
        address _swapper,
        uint256 _relayerFee,
        uint256 _feePoint,
        address _trustedRelayer,
        address _verifier,
        bytes32 _vkey
    ) public initializer {
        // initialize UntronTransfers
        __UntronTransfers_init(_spokePool, _usdt, _swapper);

        // initialize UntronFees
        __UntronFees_init(_relayerFee, _feePoint);

        // initialize UntronZK
        __UntronZK_init(_trustedRelayer, _verifier, _vkey);

        _transferOwnership(msg.sender);

        blockId = _blockId;
        stateHash = _stateHash;
        maxOrderSize = _maxOrderSize;
    }

    // UntronCore variables
    bytes32 public blockId;
    bytes32 public actionChainTip;
    bytes32 public latestExecutedAction;
    bytes32 public stateHash;
    uint256 public maxOrderSize;
    uint256 public requiredCollateral;

    /// @inheritdoc IUntronCore
    function setCoreVariables(
        bytes32 _blockId,
        bytes32 _actionChainTip,
        bytes32 _latestExecutedAction,
        bytes32 _stateHash,
        uint256 _maxOrderSize,
        uint256 _requiredCollateral
    ) external onlyOwner {
        blockId = _blockId;
        actionChainTip = _actionChainTip;
        latestExecutedAction = _latestExecutedAction;
        stateHash = _stateHash;
        maxOrderSize = _maxOrderSize;
        requiredCollateral = _requiredCollateral;
    }

    /// @notice Mapping to store provider details.
    mapping(address => Provider) internal _providers;
    /// @notice Mapping to store whether a receiver is busy with an order.
    mapping(address => bytes32) internal _isReceiverBusy;
    /// @notice Mapping to store the owner (provider) of a receiver.
    mapping(address => address) internal _receiverOwners;
    /// @notice Mapping to store order details by order ID.
    mapping(bytes32 => Order) internal _orders;

    /// @notice Returns the provider details for a given address
    /// @param provider The address of the provider
    /// @return Provider struct containing the provider's details
    function providers(address provider) external view returns (Provider memory) {
        return _providers[provider];
    }

    /// @notice Checks if a receiver is busy with an order
    /// @param receiver The address of the receiver
    /// @return bytes32 The order ID if the receiver is busy, otherwise 0
    function isReceiverBusy(address receiver) external view returns (bytes32) {
        return _isReceiverBusy[receiver];
    }

    /// @notice Returns the owner (provider) of a receiver
    /// @param receiver The address of the receiver
    /// @return address The address of the owner (provider)
    function receiverOwners(address receiver) external view returns (address) {
        return _receiverOwners[receiver];
    }

    /// @notice Returns the order details for a given order ID
    /// @param orderId The ID of the order
    /// @return Order struct containing the order details
    function orders(bytes32 orderId) external view returns (Order memory) {
        return _orders[orderId];
    }

    /// @notice Updates the action chain and returns the new tip of the chain.
    /// @param receiver The address of the receiver.
    /// @param minDeposit The minimum deposit amount.
    /// @return _actionChainTip The new action chain tip.
    /// @dev must only be used in _createOrder and _freeReceiver
    function updateActionChain(address receiver, uint256 minDeposit, uint256 size)
        internal
        returns (bytes32 _actionChainTip)
    {
        // action chain is a hash chain of the order-related, onchain-initiated actions.
        // Action consists of timestamp in Tron format, Tron receiver address, minimum deposit amount, and order size.
        // It's used to start and stop orders. If the order is stopped, minimum deposit amount is not used.
        // We're utilizing Tron timestamp to enforce the ZK program to follow all Untron actions respective to the Tron blockchain.
        // ABI: (bytes32, uint256, address, uint256, uint256)
        uint256 tronTimestamp = unixToTron(block.timestamp);
        _actionChainTip = sha256(abi.encode(actionChainTip, tronTimestamp, receiver, minDeposit, size));
        // actionChainTip stores the latest action (aka order id), that is, the tip of the action chain.
        actionChainTip = _actionChainTip;

        emit ActionChainUpdated(_actionChainTip, tronTimestamp, receiver, minDeposit, size);
    }

    /// @inheritdoc IUntronCore
    function createOrder(address provider, address receiver, uint256 size, uint256 rate, Transfer calldata transfer)
        external
    {
        // collect collateral from the order creator
        internalTransferFrom(msg.sender, requiredCollateral);

        // amount is the amount of USDT L2 that will be taken from the provider
        // based on the order size (which is in USDT Tron) and provider's rate
        (uint256 amount,) = conversion(size, rate, 0, false);
        uint256 providerMinDeposit = _providers[provider].minDeposit;

        if (_isReceiverBusy[receiver] != bytes32(0)) {
            // if the receiver is busy, check if the order that made it busy is not expired yet
            require(
                _orders[_isReceiverBusy[receiver]].timestamp + ORDER_TTL < unixToTron(block.timestamp),
                "Receiver is busy"
            );
            // if it's expired, stop it manually
            _freeReceiver(receiver);
        }
        require(_receiverOwners[receiver] == provider, "Receiver is not owned by provider");
        require(_providers[provider].liquidity >= amount, "Provider does not have enough liquidity");
        require(rate == _providers[provider].rate, "Rate does not match provider's rate");
        require(_providers[provider].minOrderSize <= size, "Order size is less than minimum");
        require(size <= maxOrderSize, "Size is greater than max order size");

        // subtract the amount from the provider's liquidity
        _providers[provider].liquidity -= amount;

        // get the previous action
        bytes32 prevAction = latestExecutedAction;
        // create the order ID and update the action chain.
        // order ID is the tip of the action chain when the order was created.
        bytes32 orderId = updateActionChain(receiver, providerMinDeposit, size);
        // set the receiver as busy to prevent double orders
        _isReceiverBusy[receiver] = orderId;
        uint256 timestamp = unixToTron(block.timestamp);
        // store the order details in storage
        _orders[orderId] = Order({
            parent: prevAction,
            timestamp: timestamp,
            creator: msg.sender,
            provider: provider,
            receiver: receiver,
            size: size,
            rate: rate,
            minDeposit: providerMinDeposit,
            collateral: requiredCollateral,
            isFulfilled: false,
            transfer: transfer
        });

        // Emit OrderCreated event
        emit OrderCreated(orderId, timestamp, msg.sender, provider, receiver, size, rate, providerMinDeposit);
    }

    /// @inheritdoc IUntronCore
    function changeOrder(bytes32 orderId, Transfer calldata transfer) external {
        require(
            _orders[orderId].creator == msg.sender && !_orders[orderId].isFulfilled, "Only creator can change the order"
        );

        // change the transfer details
        _orders[orderId].transfer = transfer;

        // Emit OrderChanged event
        emit OrderChanged(orderId);
    }

    /// @inheritdoc IUntronCore
    function stopOrder(bytes32 orderId) external {
        require(
            _orders[orderId].creator == msg.sender && !_orders[orderId].isFulfilled, "Only creator can stop the order"
        );

        // update the action chain with stop action
        _freeReceiver(_orders[orderId].receiver);

        // return the liquidity back to the provider
        _providers[_orders[orderId].provider].liquidity += _orders[orderId].size;

        // refund the collateral to the order creator
        internalTransfer(usdt, msg.sender, _orders[orderId].collateral);

        // delete the order because it won't be fulfilled/closed
        // (stopOrder assumes that the order creator sent nothing)
        delete _orders[orderId];

        // Emit OrderStopped event
        emit OrderStopped(orderId);
    }

    /// @notice Calculates the amount and fee for a given order
    /// @param order The Order struct containing order details
    /// @return amount The amount of USDT L2 that the fulfiller will have to send
    /// @return fee The fee for the fulfiller
    function _getAmountAndFee(Order memory order) internal view returns (uint256 amount, uint256 fee) {
        // calculate the fulfiller fee given the order details
        fee = calculateFee(order.transfer.doSwap, order.transfer.chainId);
        // calculate the amount of USDT L2 that the fulfiller will have to send
        (amount,) = conversion(order.size, order.rate, fee, true);
    }

    /// @notice Retrieves the active order for a given receiver
    /// @param receiver The address of the receiver
    /// @return Order struct containing the active order details
    function _getActiveOrderByReceiver(address receiver) internal view returns (Order memory) {
        // get the active order ID for the receiver
        bytes32 activeOrderId = _isReceiverBusy[receiver];
        // get the order details
        return _orders[activeOrderId];
    }

    /// @inheritdoc IUntronCore
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

    /// @inheritdoc IUntronCore
    function fulfill(address[] calldata _receivers, uint256 total) external {
        // take the declared amount of USDT L2 from the fulfiller
        internalTransferFrom(msg.sender, total);
        // this variable will be used to calculate how much the contract sent to the order creators.
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

            // refund the collateral to the order creator
            internalTransfer(usdt, order.creator, order.collateral);

            // update action chain to free the receiver address
            _freeReceiver(_receivers[i]);

            // update the order details

            // to prevent from modifying the order after it's fulfilled
            _orders[activeOrderId].creator = msg.sender;
            // to make fulfiller receive provider's USDT L2 after the ZK proof is published
            _orders[activeOrderId].transfer.recipient = msg.sender;
            // fulfiller will always receive provider's USDT L2 on the contract host chain (ZKsync Era),
            // as opposed to order creator's transfer that could be on any chain
            _orders[activeOrderId].transfer.chainId = chainId();
            // fulfilled orders don't need swaps, because the fulfillers will always receive USDT L2 on the host chain.
            _orders[activeOrderId].transfer.doSwap = false;
            // set the fulfilled order as isFullfilled true
            _orders[activeOrderId].isFulfilled = true;
            // set the collateral to 0 to prevent refunding it twice or slashing the creator wrongfully
            _orders[activeOrderId].collateral = 0;

            // Emit OrderFulfilled event
            emit OrderFulfilled(activeOrderId, msg.sender);
        }

        // check that the total amount of USDT L2 sent is less or equal to the declared amount
        require(total >= expectedTotal, "Total does not match");

        // refund the fulfiller for the USDT L2 that was sent in excess
        if (expectedTotal < total) {
            internalTransfer(usdt, msg.sender, total - expectedTotal);
        }
    }

    /// @notice Closes the orders and sends the funds to the providers or order creators, if not fulfilled.
    /// @param proof The ZK proof.
    /// @param publicValues The public values for the proof and order closure.
    function closeOrders(bytes calldata proof, bytes calldata publicValues) external {
        // verify the ZK proof with the public values
        // verifying logic is defined in the UntronZK contract.
        // currently it wraps SP1 zkVM verifier.
        verifyProof(proof, publicValues);

        (
            // old block ID must be the latest block ID that was ZK proven (blockId)
            bytes32 oldBlockId,
            // new block ID is the new latest (zk proven) block ID of Tron blockchain
            // all blocks revealed by the ZK proof are finalized in the Tron network
            bytes32 newBlockId,
            // "previous executed action" is the latest action that was executed in the previous run
            // of the ZK program. (latestExecutedAction)
            bytes32 prevExecutedAction,
            // "new executed action" is the latest action from the action chain that was executed in the current run
            // of the ZK program. it's not necessarily the latest action chain (action chain tip)
            // because the relayer might have executed some older actions that do not include the latest ones.
            // However, the new executed action must have been the action chain tip at some point.
            bytes32 newExecutedAction,
            // old state hash is the state print from the previous run of the ZK program. (stateHash)
            bytes32 oldStateHash,
            // new state hash is the state print from the new run of the ZK program.
            bytes32 newStateHash,
            // closed orders are the orders that are being closed in this run of the ZK program.
            Inflow[] memory closedOrders
        ) = abi.decode(publicValues, (bytes32, bytes32, bytes32, bytes32, bytes32, bytes32, Inflow[]));

        // check that the old block ID is the latest block ID that was ZK proven (blockId)
        require(oldBlockId == blockId, "Public input block id is not the latest ZK proven block id");
        // check that the latest (onchain) executed action is the previous executed action
        require(
            prevExecutedAction == latestExecutedAction,
            "Public input previous executed action is not the latest ZK proven action"
        );
        // check that the old state hash is equal to the current state hash
        // this is needed to prevent the relayer from modifying the state in the ZK program.
        require(oldStateHash == stateHash);

        // update the block ID, latest closed order and state hash
        blockId = newBlockId;
        latestExecutedAction = newExecutedAction;
        stateHash = newStateHash;

        // this variable is used to calculate the total fee that the protocol owner (DAO) will receiver for relayer services
        uint256 totalFee;

        // iterate over the closed orders
        for (uint256 i = 0; i < closedOrders.length; i++) {
            // get the order ID
            bytes32 orderId = closedOrders[i].order;

            // get the minimum inflow amount.
            // minInflow is the minimum number between the inflow amount on Tron and the order size.
            // this is needed so that the order creator/fulfiller doesn't get more than the order size (locked liquidity).
            uint256 minInflow =
                closedOrders[i].inflow < _orders[orderId].size ? closedOrders[i].inflow : _orders[orderId].size;

            // calculate the amount the order creator/fulfiller will receive and fee for the protocol
            (uint256 amount, uint256 fee) = conversion(minInflow, _orders[orderId].rate, 0, true);
            // add the fee to the total fee
            totalFee += fee;

            // remove fixed output flag to make the transfer unrevertable
            // (if the order creator hadn't changed the transfer details by that time it's their fault tbh)
            _orders[orderId].transfer.fixedOutput = false;

            // perform the transfer
            smartTransfer(_orders[orderId].transfer, amount);

            // if the order creator didn't send anything, slash the collateral by sending it to the protocol owner
            // otherwise refund the collateral to the order creator
            // NOTE: at fulfill() and stopOrder() we set the collateral to 0 so those actions won't lead
            // to slashing even if the order creator sent nothing
            internalTransfer(usdt, minInflow == 0 ? owner() : _orders[orderId].creator, _orders[orderId].collateral);

            if (!_orders[orderId].isFulfilled) {
                // if the order is not fulfilled, update the action chain to free the receiver address
                _freeReceiver(_orders[orderId].receiver);
            }

            // TODO: there might be a conversion bug idk

            // if not entire size is sent, send the remaining liquidity back to the provider
            (uint256 remainingLiquidity,) =
                conversion(_orders[orderId].size - minInflow, _orders[orderId].rate, 0, false);
            _providers[_orders[orderId].provider].liquidity += remainingLiquidity;

            // delete the order from storage
            delete _orders[orderId];

            // emit the OrderClosed event
            emit OrderClosed(orderId, msg.sender);
        }

        // transfer the fee to the protocol
        internalTransfer(usdt, owner(), totalFee);

        // emit the RelayUpdated event
        emit RelayUpdated(msg.sender, blockId, latestExecutedAction, stateHash);
    }

    /// @inheritdoc IUntronCore
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
            internalTransfer(usdt, msg.sender, currentLiquidity - liquidity);
        }

        // update the provider's liquidity
        _providers[msg.sender].liquidity = liquidity;

        // update the provider's rate
        _providers[msg.sender].rate = rate;
        require(minDeposit <= minOrderSize, "Min deposit is greater than min order size");
        // update the provider's minimum order size
        _providers[msg.sender].minOrderSize = minOrderSize;
        // update the provider's minimum deposit
        _providers[msg.sender].minDeposit = minDeposit;

        // iterate over receivers to ensure all are not busy or busy with already expired orders
        for (uint256 i = 0; i < receivers.length; i++) {
            // if the receiver is already busy, ensure that the order is expired
            if (_isReceiverBusy[receivers[i]] != bytes32(0)) {
                require(
                    _orders[_isReceiverBusy[receivers[i]]].timestamp + ORDER_TTL < unixToTron(block.timestamp),
                    "One of the current receivers is busy"
                );
                // set the receiver as not busy
                _freeReceiver(receivers[i]);
                // set the receiver owner to zero address
                // TODO: i don't recall if we even use _receiverOwners tbh
                _receiverOwners[receivers[i]] = address(0);
            }
        }

        // update the provider's receivers
        _providers[msg.sender].receivers = receivers;

        // check that the receivers are not already owned by another provider
        for (uint256 i = 0; i < receivers.length; i++) {
            require(
                _receiverOwners[receivers[i]] == address(0) || _receiverOwners[receivers[i]] == msg.sender,
                "Receiver is already owned by another provider"
            );
            // set the receiver owner
            _receiverOwners[receivers[i]] = msg.sender;
        }

        // Emit ProviderUpdated event
        emit ProviderUpdated(msg.sender, liquidity, rate, minOrderSize, minDeposit);
    }

    /// @notice Frees the receiver by setting it as not busy and updating the action chain with closure action.
    /// @param receiver The address of the receiver to be freed
    /// @dev does not implement checks if the closure is legitimate; must be implemented by the caller function
    function _freeReceiver(address receiver) internal {
        // set the receiver as not busy
        _isReceiverBusy[receiver] = bytes32(0);
        // update the action chain with closure action
        updateActionChain(receiver, 0, 0);
    }
}
