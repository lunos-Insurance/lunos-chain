// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title IComplianceRegistry
 * @notice Interface for the compliance credential registry.
 * @dev Stores wallet compliance credentials indexed by wallet and jurisdiction.
 *      Credentials include level, expiry, active flag, attestor, and pending updates.
 */
interface IComplianceRegistry {
    // ───────────────────────── Data Structures ─────────────────────────

    struct PendingUpdate {
        uint8 level;
        uint64 expiry;
        bool active;
        uint256 effectiveBlock;
    }

    struct Credential {
        uint8 level;
        uint64 expiry;
        bool active;
        address attestor;
        PendingUpdate pending;
    }

    // ───────────────────────── Events ──────────────────────────────────

    /// @notice Emitted when a credential update is scheduled (pending timelock).
    event CredentialScheduled(
        address indexed wallet,
        uint256 indexed jurisdiction,
        uint8 level,
        uint64 expiry,
        uint256 effectiveBlock
    );

    /// @notice Emitted when a pending credential becomes active.
    event CredentialActivated(
        address indexed wallet,
        uint256 indexed jurisdiction,
        uint8 level,
        uint64 expiry
    );

    /// @notice Emitted when a credential revocation is scheduled.
    event CredentialRevoked(
        address indexed wallet,
        uint256 indexed jurisdiction
    );

    // ───────────────────────── Functions ───────────────────────────────

    /**
     * @notice Returns the credential for a wallet in a given jurisdiction.
     * @param wallet The wallet address.
     * @param jurisdiction The jurisdiction identifier.
     * @return credential The Credential struct.
     */
    function getCredential(address wallet, uint256 jurisdiction)
        external
        view
        returns (Credential memory credential);

    /**
     * @notice Submits a new credential for a wallet.
     * @dev Only approved attestors may call this. The credential is scheduled
     *      with a pending update that activates after the global delay.
     * @param wallet The wallet address.
     * @param jurisdiction The jurisdiction identifier.
     * @param level The compliance level (Retail < Accredited < Institutional).
     * @param expiry The expiration timestamp for the credential.
     */
    function submitCredential(
        address wallet,
        uint256 jurisdiction,
        uint8 level,
        uint64 expiry
    ) external;

    /**
     * @notice Schedules an update to an existing credential.
     * @dev Only approved attestors may call this. Update respects global delay.
     * @param wallet The wallet address.
     * @param jurisdiction The jurisdiction identifier.
     * @param level The new compliance level.
     * @param expiry The new expiration timestamp.
     */
    function scheduleCredentialUpdate(
        address wallet,
        uint256 jurisdiction,
        uint8 level,
        uint64 expiry
    ) external;

    /**
     * @notice Schedules a revocation for a credential.
     * @dev May be called by the credential's attestor or governance.
     *      Revocation respects global delay.
     * @param wallet The wallet address.
     * @param jurisdiction The jurisdiction identifier.
     */
    function scheduleCredentialRevocation(
        address wallet,
        uint256 jurisdiction
    ) external;

    /**
     * @notice Resolves any pending update for a credential if the effective block has passed.
     * @dev This is called lazily during reads (e.g. during transfer validation).
     * @param wallet The wallet address.
     * @param jurisdiction The jurisdiction identifier.
     */
    function resolveCredential(
        address wallet,
        uint256 jurisdiction
    ) external;

    /**
     * @notice Returns the pending update for a credential.
     * @param wallet The wallet address.
     * @param jurisdiction The jurisdiction identifier.
     * @return pending The PendingUpdate struct.
     */
    function getPendingCredential(address wallet, uint256 jurisdiction)
        external
        view
        returns (PendingUpdate memory pending);
}
