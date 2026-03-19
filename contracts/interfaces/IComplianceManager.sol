// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title IComplianceManager
 * @notice Interface for the compliance validation engine.
 * @dev Validates transfer eligibility based on credentials, levels, expiry, and
 *      jurisdiction-matrix compatibility. Must NOT modify state — view/pure only.
 */
interface IComplianceManager {
    /**
     * @notice Validates whether a transfer between two wallets is compliant.
     * @dev Must be a view function — no state mutations allowed.
     * @param sender The address sending tokens.
     * @param receiver The address receiving tokens.
     * @param senderJurisdiction The jurisdiction of the sender's credential.
     * @param receiverJurisdiction The jurisdiction of the receiver's credential.
     * @param requiredLevel The minimum compliance level required by the token.
     * @return isValid True if the transfer is compliant, false otherwise.
     */
    function validateTransfer(
        address sender,
        address receiver,
        uint256 senderJurisdiction,
        uint256 receiverJurisdiction,
        uint8 requiredLevel
    ) external view returns (bool isValid);
}
