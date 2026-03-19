// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../interfaces/IComplianceManager.sol";
import "../interfaces/IComplianceRegistry.sol";
import "../interfaces/IJurisdictionRegistry.sol";

/**
 * @title ComplianceManager
 * @notice Evaluates compliance rules for token transfers.
 * @dev Reads from ComplianceRegistry, JurisdictionRegistry, and TokenTransferMatrix.
 *      Performs view-only validation — MUST NOT modify any state.
 *      All lookups are O(1) via mappings.
 *
 * Storage layout:
 *   - IComplianceRegistry complianceRegistry
 *   - IJurisdictionRegistry jurisdictionRegistry
 *   - uint256[48] __gap
 */
contract ComplianceManager is
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    IComplianceManager
{
    // ───────────────────────── Storage ─────────────────────────────────

    /// @notice Reference to the ComplianceRegistry contract.
    IComplianceRegistry public complianceRegistry;

    /// @notice Reference to the JurisdictionRegistry contract.
    IJurisdictionRegistry public jurisdictionRegistry;

    /// @dev Reserved storage gap for future upgrades.
    uint256[48] private __gap;

    // ───────────────────────── Errors ──────────────────────────────────

    /// @dev Thrown when an invalid address is provided.
    error InvalidAddress();

    // ───────────────────────── Initializer ─────────────────────────────

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the ComplianceManager.
     * @param governance The address that will own the contract (governance multisig).
     * @param _complianceRegistry The address of the ComplianceRegistry contract.
     * @param _jurisdictionRegistry The address of the JurisdictionRegistry contract.
     */
    function initialize(
        address governance,
        address _complianceRegistry,
        address _jurisdictionRegistry
    ) external initializer {
        if (_complianceRegistry == address(0) || _jurisdictionRegistry == address(0)) {
            revert InvalidAddress();
        }

        __Ownable_init(governance);

        complianceRegistry = IComplianceRegistry(_complianceRegistry);
        jurisdictionRegistry = IJurisdictionRegistry(_jurisdictionRegistry);
    }

    // ───────────────────────── External Functions ──────────────────────

    /**
     * @inheritdoc IComplianceManager
     * @dev Performs the following checks in order:
     *      1. Sender credential exists and is active
     *      2. Receiver credential exists and is active
     *      3. Sender credential not expired
     *      4. Receiver credential not expired
     *      5. Sender credential level >= requiredLevel
     *      6. Receiver credential level >= requiredLevel
     *      7. Both jurisdictions are registered
     *      Note: Matrix compatibility is checked by the token contract via TokenTransferMatrix.
     */
    function validateTransfer(
        address sender,
        address receiver,
        uint256 senderJurisdiction,
        uint256 receiverJurisdiction,
        uint8 requiredLevel
    ) external view returns (bool isValid) {
        // 1. Retrieve credentials
        IComplianceRegistry.Credential memory senderCred =
            complianceRegistry.getCredential(sender, senderJurisdiction);
        IComplianceRegistry.Credential memory receiverCred =
            complianceRegistry.getCredential(receiver, receiverJurisdiction);

        // 2. Check sender credential active
        if (!senderCred.active) return false;

        // 3. Check receiver credential active
        if (!receiverCred.active) return false;

        // 4. Check sender credential expiry
        if (block.timestamp >= senderCred.expiry) return false;

        // 5. Check receiver credential expiry
        if (block.timestamp >= receiverCred.expiry) return false;

        // 6. Check sender compliance level
        if (senderCred.level < requiredLevel) return false;

        // 7. Check receiver compliance level
        if (receiverCred.level < requiredLevel) return false;

        // 8. Check jurisdictions are registered
        if (!jurisdictionRegistry.jurisdictionExists(senderJurisdiction)) return false;
        if (!jurisdictionRegistry.jurisdictionExists(receiverJurisdiction)) return false;

        return true;
    }

    // ───────────────────────── Governance Functions ────────────────────

    /**
     * @notice Updates the ComplianceRegistry address.
     * @dev Only governance (owner) may call this.
     * @param _complianceRegistry The new ComplianceRegistry address.
     */
    function setComplianceRegistry(address _complianceRegistry) external onlyOwner {
        if (_complianceRegistry == address(0)) revert InvalidAddress();
        complianceRegistry = IComplianceRegistry(_complianceRegistry);
    }

    /**
     * @notice Updates the JurisdictionRegistry address.
     * @dev Only governance (owner) may call this.
     * @param _jurisdictionRegistry The new JurisdictionRegistry address.
     */
    function setJurisdictionRegistry(address _jurisdictionRegistry) external onlyOwner {
        if (_jurisdictionRegistry == address(0)) revert InvalidAddress();
        jurisdictionRegistry = IJurisdictionRegistry(_jurisdictionRegistry);
    }

    // ───────────────────────── Internal ────────────────────────────────

    /**
     * @dev Authorizes contract upgrades — only the owner (governance) may upgrade.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
