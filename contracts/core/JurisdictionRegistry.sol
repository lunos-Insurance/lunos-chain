// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../interfaces/IJurisdictionRegistry.sol";

/**
 * @title JurisdictionRegistry
 * @notice Stores canonical jurisdiction identifiers for the compliance system.
 * @dev Only governance (owner) may add jurisdictions. Jurisdiction IDs are
 *      immutable once created and can never be removed. Uses UUPS upgrade pattern.
 *
 * Storage layout:
 *   - mapping(uint256 => bool) _jurisdictions
 *   - uint256[50] __gap
 */
contract JurisdictionRegistry is
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    IJurisdictionRegistry
{
    // ───────────────────────── Storage ─────────────────────────────────

    /// @notice Maps jurisdiction ID to existence flag.
    mapping(uint256 => bool) private _jurisdictions;

    /// @dev Reserved storage gap for future upgrades.
    uint256[50] private __gap;

    // ───────────────────────── Errors ──────────────────────────────────

    /// @dev Thrown when attempting to add a jurisdiction that already exists.
    error JurisdictionAlreadyExists(uint256 jurisdictionId);

    /// @dev Thrown when referencing a jurisdiction that does not exist.
    error JurisdictionDoesNotExist(uint256 jurisdictionId);

    // ───────────────────────── Initializer ─────────────────────────────

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the JurisdictionRegistry.
     * @param governance The address that will own the contract (governance multisig).
     */
    function initialize(address governance) external initializer {
        __Ownable_init(governance);
    }

    // ───────────────────────── External Functions ──────────────────────

    /// @inheritdoc IJurisdictionRegistry
    function addJurisdiction(uint256 jurisdictionId) external onlyOwner {
        if (_jurisdictions[jurisdictionId]) {
            revert JurisdictionAlreadyExists(jurisdictionId);
        }
        _jurisdictions[jurisdictionId] = true;
        emit JurisdictionAdded(jurisdictionId);
    }

    /// @inheritdoc IJurisdictionRegistry
    function jurisdictionExists(uint256 jurisdictionId) external view returns (bool exists) {
        return _jurisdictions[jurisdictionId];
    }

    // ───────────────────────── Internal ────────────────────────────────

    /**
     * @dev Authorizes contract upgrades — only the owner (governance) may upgrade.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
