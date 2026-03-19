// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title IAttestor
 * @notice Interface for the approved attestor registry.
 * @dev Attestors are external KYC providers whitelisted by governance
 *      to submit compliance credentials on-chain.
 */
interface IAttestor {
    // ───────────────────────── Events ──────────────────────────────────

    /// @notice Emitted when a new attestor is approved.
    event AttestorAdded(address indexed attestor);

    /// @notice Emitted when an attestor is removed.
    event AttestorRemoved(address indexed attestor);

    // ───────────────────────── Functions ───────────────────────────────

    /**
     * @notice Adds an address as an approved attestor.
     * @dev Only governance may call this.
     * @param attestor The address to approve as attestor.
     */
    function addAttestor(address attestor) external;

    /**
     * @notice Removes an address from the approved attestors.
     * @dev Only governance may call this.
     * @param attestor The address to remove.
     */
    function removeAttestor(address attestor) external;

    /**
     * @notice Checks whether an address is an approved attestor.
     * @param attestor The address to check.
     * @return approved True if the address is an approved attestor.
     */
    function isAttestor(address attestor) external view returns (bool approved);
}
