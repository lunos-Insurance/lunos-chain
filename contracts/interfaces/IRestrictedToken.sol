// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title IRestrictedToken
 * @notice Interface for the compliance-enabled restricted ERC20 token.
 * @dev Tokens enforce compliance in `_beforeTokenTransfer`. Once compliance is
 *      enabled it can never be disabled.
 */
interface IRestrictedToken {
    // ───────────────────────── Events ──────────────────────────────────

    /// @notice Emitted when a compliance check fails during a transfer.
    event ComplianceCheckFailed(
        address indexed sender,
        address indexed receiver,
        string reason
    );

    /// @notice Emitted when a restricted token transfer succeeds.
    event RestrictedTokenTransfer(
        address indexed sender,
        address indexed receiver,
        uint256 amount
    );

    // ───────────────────────── Functions ───────────────────────────────

    /**
     * @notice Mints tokens to a specified address.
     * @dev Only the issuer (owner) may call this.
     * @param to The recipient address.
     * @param amount The amount of tokens to mint.
     */
    function mint(address to, uint256 amount) external;

    /**
     * @notice Burns tokens from a specified address.
     * @dev Only the issuer (owner) may call this.
     * @param from The address to burn tokens from.
     * @param amount The amount of tokens to burn.
     */
    function burn(address from, uint256 amount) external;

    /**
     * @notice Sets the minimum compliance level required for transfers.
     * @dev Only the issuer (owner) may call this.
     * @param level The required compliance level (Retail=1, Accredited=2, Institutional=3).
     */
    function setRequiredLevel(uint8 level) external;

    /**
     * @notice Updates the jurisdiction transfer matrix for this token.
     * @dev Only the issuer (owner) may call this. Updates respect token delay.
     * @param fromJurisdiction The source jurisdiction identifier.
     * @param toJurisdiction The destination jurisdiction identifier.
     * @param allowed Whether transfers between these jurisdictions are allowed.
     */
    function updateMatrix(
        uint256 fromJurisdiction,
        uint256 toJurisdiction,
        bool allowed
    ) external;
}
