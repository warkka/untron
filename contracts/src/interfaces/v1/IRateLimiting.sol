// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

interface IRateLimiting {
    function REGISTRAR_ROLE() external view returns (bytes32);
    function rate() external view returns (uint256);
    function per() external view returns (uint256);
    function isRegistered(address user) external view returns (bool);

    function changeRateLimit(uint256 _rate, uint256 _per) external;

    /// @notice Registers the `user`.
    /// @dev Reverts if the `user` is not allowed to register.
    /// @param user the address we want to register
    /// @param data ABI-encoded registrar's signature of keccak256(abi.encode(user, true)).
    ///             Follows structure (uint8 v, bytes32 r, bytes32 s)
    function register(address user, bytes calldata data) external;

    /// @notice Unregisters the `user`.
    /// @dev Reverts if the `user` is not allowed to register.
    /// @param user the address we want to unregister
    /// @param data ABI-encoded registrar's signature of keccak256(abi.encode(user, false)).
    ///             Follows structure (uint8 v, bytes32 r, bytes32 s)
    function unregister(address user, bytes calldata data) external;
}
