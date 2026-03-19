// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title TokenTransferMatrix
 * @notice Stores jurisdiction-to-jurisdiction transfer compatibility for a token.
 * @dev Issuer-controlled matrix with timelocked updates. Each token has its own
 *      matrix instance. Matrix lookups are O(1) via nested mappings.
 *      Uses UUPS upgrade pattern.
 *
 * Storage layout:
 *   - mapping(uint256 => mapping(uint256 => bool)) _matrix
 *   - mapping(bytes32 => PendingMatrixUpdate) _pendingUpdates
 *   - uint256 tokenDelay
 *   - uint256[47] __gap
 */
contract TokenTransferMatrix is
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    // ───────────────────────── Data Structures ─────────────────────────

    /// @notice Pending matrix update awaiting timelock expiry.
    struct PendingMatrixUpdate {
        bool allowed;
        uint256 effectiveBlock;
        bool exists;
    }

    // ───────────────────────── Storage ─────────────────────────────────

    /// @notice Jurisdiction compatibility matrix: from => to => allowed.
    mapping(uint256 => mapping(uint256 => bool)) private _matrix;

    /// @notice Pending matrix updates, keyed by keccak256(fromJurisdiction, toJurisdiction).
    mapping(bytes32 => PendingMatrixUpdate) private _pendingUpdates;

    /// @notice Issuer-controlled delay (in blocks) for matrix updates.
    uint256 public tokenDelay;

    /// @dev Reserved storage gap for future upgrades.
    uint256[47] private __gap;

    // ───────────────────────── Events ──────────────────────────────────

    /// @notice Emitted when a matrix update is scheduled.
    event MatrixUpdateScheduled(
        uint256 indexed fromJurisdiction,
        uint256 indexed toJurisdiction,
        bool allowed,
        uint256 effectiveBlock
    );

    /// @notice Emitted when a pending matrix update is activated.
    event MatrixUpdateActivated(
        uint256 indexed fromJurisdiction,
        uint256 indexed toJurisdiction,
        bool allowed
    );

    // ───────────────────────── Errors ──────────────────────────────────

    /// @dev Thrown when there is no pending update to resolve.
    error NoPendingUpdate(uint256 fromJurisdiction, uint256 toJurisdiction);

    // ───────────────────────── Initializer ─────────────────────────────

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the TokenTransferMatrix.
     * @param issuer The address that will own the matrix (token issuer).
     * @param _tokenDelay The initial token delay in blocks for matrix updates.
     */
    function initialize(address issuer, uint256 _tokenDelay) external initializer {
        __Ownable_init(issuer);
        tokenDelay = _tokenDelay;
    }

    // ───────────────────────── External Functions ──────────────────────

    /**
     * @notice Schedules a matrix update with timelock.
     * @dev Only the issuer (owner) may call this. Update takes effect after tokenDelay blocks.
     * @param fromJurisdiction The source jurisdiction identifier.
     * @param toJurisdiction The destination jurisdiction identifier.
     * @param allowed Whether transfers from source to destination should be allowed.
     */
    function scheduleMatrixUpdate(
        uint256 fromJurisdiction,
        uint256 toJurisdiction,
        bool allowed
    ) external onlyOwner {
        uint256 effectiveBlock = block.number + tokenDelay;
        bytes32 key = _matrixKey(fromJurisdiction, toJurisdiction);

        _pendingUpdates[key] = PendingMatrixUpdate({
            allowed: allowed,
            effectiveBlock: effectiveBlock,
            exists: true
        });

        emit MatrixUpdateScheduled(fromJurisdiction, toJurisdiction, allowed, effectiveBlock);
    }

    /**
     * @notice Resolves a pending matrix update if the effective block has passed.
     * @dev Can be called by anyone — lazy activation model.
     * @param fromJurisdiction The source jurisdiction identifier.
     * @param toJurisdiction The destination jurisdiction identifier.
     */
    function resolveMatrixUpdate(
        uint256 fromJurisdiction,
        uint256 toJurisdiction
    ) external {
        _resolveMatrixUpdate(fromJurisdiction, toJurisdiction);
    }

    /**
     * @notice Checks whether a transfer between two jurisdictions is allowed.
     * @param fromJurisdiction The source jurisdiction identifier.
     * @param toJurisdiction The destination jurisdiction identifier.
     * @return allowed True if the transfer is allowed by the matrix.
     */
    function matrixAllows(
        uint256 fromJurisdiction,
        uint256 toJurisdiction
    ) external view returns (bool allowed) {
        return _matrix[fromJurisdiction][toJurisdiction];
    }

    /**
     * @notice Returns the pending matrix update for a jurisdiction pair.
     * @param fromJurisdiction The source jurisdiction identifier.
     * @param toJurisdiction The destination jurisdiction identifier.
     * @return update The PendingMatrixUpdate struct.
     */
    function getPendingMatrixUpdate(
        uint256 fromJurisdiction,
        uint256 toJurisdiction
    ) external view returns (PendingMatrixUpdate memory update) {
        bytes32 key = _matrixKey(fromJurisdiction, toJurisdiction);
        return _pendingUpdates[key];
    }

    /**
     * @notice Updates the token delay for matrix updates.
     * @dev Only the issuer (owner) may call this.
     * @param newDelay The new token delay in blocks.
     */
    function setTokenDelay(uint256 newDelay) external onlyOwner {
        tokenDelay = newDelay;
        // TODO: emit event for delay change
    }

    // ───────────────────────── Internal Functions ──────────────────────

    /**
     * @dev Resolves a pending matrix update if the effective block has passed.
     * @param fromJurisdiction The source jurisdiction identifier.
     * @param toJurisdiction The destination jurisdiction identifier.
     */
    function _resolveMatrixUpdate(
        uint256 fromJurisdiction,
        uint256 toJurisdiction
    ) internal {
        bytes32 key = _matrixKey(fromJurisdiction, toJurisdiction);
        PendingMatrixUpdate storage pending = _pendingUpdates[key];

        if (!pending.exists) {
            revert NoPendingUpdate(fromJurisdiction, toJurisdiction);
        }

        if (block.number >= pending.effectiveBlock) {
            _matrix[fromJurisdiction][toJurisdiction] = pending.allowed;

            emit MatrixUpdateActivated(fromJurisdiction, toJurisdiction, pending.allowed);

            delete _pendingUpdates[key];
        }
    }

    /**
     * @dev Computes the storage key for a jurisdiction pair.
     * @param fromJurisdiction The source jurisdiction identifier.
     * @param toJurisdiction The destination jurisdiction identifier.
     * @return key The keccak256 hash of the jurisdiction pair.
     */
    function _matrixKey(
        uint256 fromJurisdiction,
        uint256 toJurisdiction
    ) internal pure returns (bytes32 key) {
        return keccak256(abi.encodePacked(fromJurisdiction, toJurisdiction));
    }

    /**
     * @dev Authorizes contract upgrades — only the owner (issuer) may upgrade.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
