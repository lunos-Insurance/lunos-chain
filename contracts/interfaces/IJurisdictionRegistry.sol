// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title IJurisdictionRegistry
 * @notice Interface for the canonical jurisdiction identifier registry.
 * @dev Jurisdiction IDs are immutable once created. Only governance may add jurisdictions.
 */
interface IJurisdictionRegistry {
    // ───────────────────────── Events ──────────────────────────────────

    /// @notice Emitted when a new jurisdiction is registered.
    event JurisdictionAdded(uint256 indexed jurisdictionId);

    // ───────────────────────── Functions ───────────────────────────────

    /**
     * @notice Registers a new jurisdiction identifier.
     * @dev Only governance may call this. Jurisdiction IDs are immutable once created.
     * @param jurisdictionId The unique jurisdiction identifier (e.g. 1=EU, 2=US, 3=UAE).
     */
    function addJurisdiction(uint256 jurisdictionId) external;

    /**
     * @notice Checks whether a jurisdiction identifier exists.
     * @param jurisdictionId The jurisdiction identifier to check.
     * @return exists True if the jurisdiction has been registered.
     */
    function jurisdictionExists(uint256 jurisdictionId) external view returns (bool exists);
}
