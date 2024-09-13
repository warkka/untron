// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

/// @title Rate limiting for smart contracts
/// @author Ultrasound Labs
/// @notice This paymaster allows to register users and limit their actions per time period.
contract RateLimiting is AccessControlUpgradeable {
    bytes32 public constant REGISTRAR_ROLE = keccak256("REGISTRAR_ROLE");

    uint256 public rate;
    uint256 public per;
    mapping(address => bool) public isRegistered;
    mapping(bytes4 => mapping(address => uint256[])) internal calls;

    function _changeRate(uint256 _rate, uint256 _per) internal {
        rate = _rate;
        per = _per;
    }

    /// @notice Returns whether the signature was made by one of registrars for `data`
    /// @dev `data` is keccak256 hashed before verification.
    /// @param data byte array that was signed. It's keccak256 hashed before verification.
    /// @param signature ABI-encoded signature. Follows structure (uint8 v, bytes32 r, bytes32 s)
    /// @return bool true if the signature was made by one of registrars for `data`,
    ///              false otherwise
    function _isValidSignature(bytes memory data, bytes memory signature) private view returns (bool) {
        // ABI-decode `signature` bytes into v, r, s (parts of the signature)
        (uint8 v, bytes32 r, bytes32 s) = abi.decode(signature, (uint8, bytes32, bytes32));
        // recover the signer address from signature and keccak256-hashed `data`
        address signer = ecrecover(keccak256(data), v, r, s);
        // return if `signer` is a registrar
        return hasRole(REGISTRAR_ROLE, signer);
    }

    /// @notice Registers the `user`.
    /// @dev Reverts if the `user` is not allowed to register.
    /// @param user the address we want to register
    /// @param data ABI-encoded registrar's signature of keccak256(abi.encode(user, true)).
    ///             Follows structure (uint8 v, bytes32 r, bytes32 s)
    function register(address user, bytes calldata data) internal view {
        require(
            hasRole(REGISTRAR_ROLE, msg.sender) || _isValidSignature(abi.encode(user, true), data),
            "registration denied"
        );
    }

    /// @notice Unregisters the `user`.
    /// @dev Reverts if the `user` is not allowed to register.
    /// @param user the address we want to unregister
    /// @param data ABI-encoded registrar's signature of keccak256(abi.encode(user, false)).
    ///             Follows structure (uint8 v, bytes32 r, bytes32 s)
    function unregister(address user, bytes calldata data) internal view {
        require(
            hasRole(REGISTRAR_ROLE, msg.sender) || _isValidSignature(abi.encode(user, false), data),
            "unregistration denied"
        );
    }

    /// @notice Returns whether the delay for the call has passed
    /// @dev Used by exported modifiers
    /// @param selector function selector of the action
    /// @param user address of the user
    /// @param offset index of the action we check starting from the end (offset = actions.length-offset):
    ///               0 -> we get last action
    ///               1 -> we get penultimate action or the first one if there's been only 1 action
    ///               2 -> we get action at offset min(0, actions.length-3)
    ///               3 -> we get action at offset min(0, actions.length-4)
    ///               ... etc
    /// @param delay how much time has to pass between block.timestamp and action at offset
    /// @return bool whether delay has passed (true) or not (false)
    function _hasDelayPassed(bytes4 selector, address user, uint256 offset, uint256 delay)
        internal
        view
        returns (bool)
    {
        // unregistered users are delayed forever
        if (!isRegistered[user]) {
            return false;
        }
        // store pointer to `calls[selector]` mapping.
        mapping(address => uint256[]) storage journal = calls[selector];

        // return true if there are less elements in `journal[user]` than `offset`+1 OR
        // if offset-th element in `journal[user]` starting from the end and block.timestamp
        // are different by at least `delay`
        //
        // what is happening:
        // we want to check whether the offset-th last action of the user has happened at least `delay` seconds ago.
        // if it did indeed happen with this delay OR there were less actions than could be indexed with this offset,
        // we return true (delay has passed). otherwise, we return false.
        return (journal[user].length <= offset)
            || journal[user][journal[user].length - 1 - offset] + delay <= block.timestamp;
    }

    function _logCall(address user, bytes4 selector) internal {
        calls[selector][user].push(block.timestamp);
    }

    function _selector() internal pure returns (bytes4 selector) {
        assembly {
            selector := calldataload(0)
        }
    }
}
