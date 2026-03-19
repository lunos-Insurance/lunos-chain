// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title FeeManager
 * @notice Placeholder for future fee routing module.
 * @dev Future module — will handle issuer fees, attestation fees, and protocol fees.
 *      This is a minimal placeholder for future upgrades.
 *
 * Storage layout:
 *   - uint256 protocolFeeBps
 *   - address feeRecipient
 *   - uint256[48] __gap
 */
contract FeeManager is
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    // ───────────────────────── Storage ─────────────────────────────────

    /// @notice Protocol fee in basis points (1 bps = 0.01%).
    uint256 public protocolFeeBps;

    /// @notice Address that receives protocol fees.
    address public feeRecipient;

    /// @dev Reserved storage gap for future upgrades.
    uint256[48] private __gap;

    // ───────────────────────── Events ──────────────────────────────────

    /// @notice Emitted when the protocol fee is updated.
    event ProtocolFeeUpdated(uint256 newFeeBps);

    /// @notice Emitted when the fee recipient is updated.
    event FeeRecipientUpdated(address indexed newRecipient);

    // ───────────────────────── Initializer ─────────────────────────────

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the FeeManager.
     * @param governance The address that will own the fee manager (governance multisig).
     */
    function initialize(address governance) external initializer {
        __Ownable_init(governance);
    }

    // ───────────────────────── External Functions ──────────────────────

    /**
     * @notice Sets the protocol fee in basis points.
     * @dev Only governance (owner) may call this. TODO: implement fee collection logic.
     * @param feeBps The new protocol fee in basis points.
     */
    function setProtocolFee(uint256 feeBps) external onlyOwner {
        // TODO: add max fee validation
        protocolFeeBps = feeBps;
        emit ProtocolFeeUpdated(feeBps);
    }

    /**
     * @notice Sets the fee recipient address.
     * @dev Only governance (owner) may call this.
     * @param recipient The new fee recipient.
     */
    function setFeeRecipient(address recipient) external onlyOwner {
        // TODO: add zero-address validation
        feeRecipient = recipient;
        emit FeeRecipientUpdated(recipient);
    }

    // ───────────────────────── Internal ────────────────────────────────

    /**
     * @dev Authorizes contract upgrades — only the owner (governance) may upgrade.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
