// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../interfaces/IAttestor.sol";

/**
 * @title ApprovedAttestors
 * @notice Registry of approved attestor addresses that can issue compliance credentials.
 * @dev Governance (owner) adds and removes attestors. Attestors are external KYC providers
 *      that submit compliance credentials on-chain. Uses UUPS upgrade pattern.
 *
 * Storage layout:
 *   - mapping(address => bool) _approvedAttestors
 *   - uint256[50] __gap
 */
contract ApprovedAttestors is
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    IAttestor
{
    // ───────────────────────── Storage ─────────────────────────────────

    /// @notice Maps attestor address to approval status.
    mapping(address => bool) private _approvedAttestors;

    /// @dev Reserved storage gap for future upgrades.
    uint256[50] private __gap;

    // ───────────────────────── Errors ──────────────────────────────────

    /// @dev Thrown when the attestor is already approved.
    error AttestorAlreadyApproved(address attestor);

    /// @dev Thrown when the attestor is not approved.
    error AttestorNotApproved(address attestor);

    /// @dev Thrown when an invalid address is provided.
    error InvalidAddress();

    // ───────────────────────── Initializer ─────────────────────────────

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the ApprovedAttestors registry.
     * @param governance The address that will own the contract (governance multisig).
     */
    function initialize(address governance) external initializer {
        __Ownable_init(governance);
    }

    // ───────────────────────── External Functions ──────────────────────

    /// @inheritdoc IAttestor
    function addAttestor(address attestor) external onlyOwner {
        if (attestor == address(0)) revert InvalidAddress();
        if (_approvedAttestors[attestor]) revert AttestorAlreadyApproved(attestor);

        _approvedAttestors[attestor] = true;
        emit AttestorAdded(attestor);
    }

    /// @inheritdoc IAttestor
    function removeAttestor(address attestor) external onlyOwner {
        if (!_approvedAttestors[attestor]) revert AttestorNotApproved(attestor);

        _approvedAttestors[attestor] = false;
        emit AttestorRemoved(attestor);
    }

    /// @inheritdoc IAttestor
    function isAttestor(address attestor) external view returns (bool approved) {
        return _approvedAttestors[attestor];
    }

    // ───────────────────────── Internal ────────────────────────────────

    /**
     * @dev Authorizes contract upgrades — only the owner (governance) may upgrade.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
