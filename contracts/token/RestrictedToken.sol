// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../interfaces/IRestrictedToken.sol";
import "../interfaces/IComplianceManager.sol";
import "../interfaces/IComplianceRegistry.sol";
import "./TokenTransferMatrix.sol";

/**
 * @title RestrictedToken
 * @notice Compliance-enabled upgradeable ERC20 token for regulated zk-validium chain.
 * @dev Enforces compliance in `_beforeTokenTransfer()`. Once compliance is enabled,
 *      it can NEVER be disabled (security invariant). Uses UUPS upgrade pattern.
 *
 * Storage layout:
 *   - bool complianceEnabled                         (slot inherited)
 *   - uint8 requiredLevel                            (packed with above)
 *   - address complianceManager
 *   - address complianceRegistry
 *   - address matrixContract
 *   - mapping(uint256 => bool) acceptedJurisdictions
 *   - uint256[44] __gap
 *
 * Transfer validation flow (in _beforeTokenTransfer):
 *   1. Resolve sender credential (lazy activation)
 *   2. Resolve receiver credential (lazy activation)
 *   3. Validate via ComplianceManager (active, expiry, level)
 *   4. Check matrix compatibility via TokenTransferMatrix
 *   5. Revert with ComplianceCheckFailed event if invalid
 */
contract RestrictedToken is
    Initializable,
    ERC20Upgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    IRestrictedToken
{
    // ───────────────────────── Storage ─────────────────────────────────

    /// @notice Whether compliance enforcement is active. Cannot be set to false once true.
    bool public complianceEnabled;

    /// @notice Minimum compliance level required for transfers.
    uint8 public requiredLevel;

    /// @notice Address of the ComplianceManager contract.
    address public complianceManager;

    /// @notice Address of the ComplianceRegistry contract.
    address public complianceRegistry;

    /// @notice Address of the TokenTransferMatrix contract for this token.
    address public matrixContract;

    /// @notice Jurisdictions accepted by this token.
    mapping(uint256 => bool) public acceptedJurisdictions;

    /// @notice Default sender jurisdiction for compliance lookups.
    /// @dev Wallets must declare which jurisdiction to use for this token.
    mapping(address => uint256) public walletJurisdiction;

    /// @dev Reserved storage gap for future upgrades.
    uint256[44] private __gap;

    // ───────────────────────── Errors ──────────────────────────────────

    /// @dev Thrown when attempting to disable compliance.
    error ComplianceCannotBeDisabled();

    /// @dev Thrown when compliance check fails during transfer.
    error TransferNotCompliant(string reason);

    /// @dev Thrown when an invalid address is provided.
    error InvalidAddress();

    // ───────────────────────── Events ──────────────────────────────────

    /// @notice Emitted when compliance is enabled for this token.
    event ComplianceEnabledSet(bool enabled);

    /// @notice Emitted when the required compliance level is updated.
    event RequiredLevelUpdated(uint8 newLevel);

    /// @notice Emitted when a jurisdiction is added or removed from accepted list.
    event AcceptedJurisdictionUpdated(uint256 indexed jurisdictionId, bool accepted);

    /// @notice Emitted when a wallet sets its jurisdiction for this token.
    event WalletJurisdictionSet(address indexed wallet, uint256 jurisdictionId);

    // ───────────────────────── Initializer ─────────────────────────────

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the RestrictedToken.
     * @param name_ The token name.
     * @param symbol_ The token symbol.
     * @param issuer The address that will own the token (issuer).
     * @param _complianceManager The address of the ComplianceManager contract.
     * @param _complianceRegistry The address of the ComplianceRegistry contract.
     * @param _matrixContract The address of the TokenTransferMatrix for this token.
     * @param _requiredLevel The minimum compliance level required.
     */
    function initialize(
        string memory name_,
        string memory symbol_,
        address issuer,
        address _complianceManager,
        address _complianceRegistry,
        address _matrixContract,
        uint8 _requiredLevel
    ) external initializer {
        __ERC20_init(name_, symbol_);
        __Ownable_init(issuer);

        complianceManager = _complianceManager;
        complianceRegistry = _complianceRegistry;
        matrixContract = _matrixContract;
        requiredLevel = _requiredLevel;
        complianceEnabled = true; // Always starts enabled — cannot be disabled

        emit ComplianceEnabledSet(true);
    }

    // ───────────────────────── External Functions ──────────────────────

    /// @inheritdoc IRestrictedToken
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /// @inheritdoc IRestrictedToken
    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }

    /// @inheritdoc IRestrictedToken
    function setRequiredLevel(uint8 level) external onlyOwner {
        requiredLevel = level;
        emit RequiredLevelUpdated(level);
    }

    /// @inheritdoc IRestrictedToken
    function updateMatrix(
        uint256 fromJurisdiction,
        uint256 toJurisdiction,
        bool allowed
    ) external onlyOwner {
        TokenTransferMatrix(matrixContract).scheduleMatrixUpdate(
            fromJurisdiction,
            toJurisdiction,
            allowed
        );
    }

    /**
     * @notice Adds or removes a jurisdiction from the accepted list for this token.
     * @dev Only the issuer (owner) may call this.
     * @param jurisdictionId The jurisdiction identifier.
     * @param accepted Whether the jurisdiction should be accepted.
     */
    function setAcceptedJurisdiction(uint256 jurisdictionId, bool accepted) external onlyOwner {
        acceptedJurisdictions[jurisdictionId] = accepted;
        emit AcceptedJurisdictionUpdated(jurisdictionId, accepted);
    }

    /**
     * @notice Allows a wallet to declare its jurisdiction for this token.
     * @dev Wallets must set this before they can receive transfers.
     * @param jurisdictionId The jurisdiction to use for compliance lookups.
     */
    function setWalletJurisdiction(uint256 jurisdictionId) external {
        walletJurisdiction[msg.sender] = jurisdictionId;
        emit WalletJurisdictionSet(msg.sender, jurisdictionId);
    }

    // ───────────────────────── Internal Hooks ──────────────────────────

    /**
     * @dev Hook called before any token transfer (including mint and burn).
     *      Enforces compliance validation when complianceEnabled == true.
     *
     *      Validation sequence:
     *        1. Skip compliance for mints (from == address(0)) and burns (to == address(0))
     *        2. Resolve sender and receiver credentials (lazy activation)
     *        3. Look up wallet jurisdictions
     *        4. Verify jurisdictions are accepted by this token
     *        5. Validate via ComplianceManager (active, expiry, level)
     *        6. Check matrix compatibility
     *        7. Emit ComplianceCheckFailed and revert if invalid
     *
     * @param from The sender address.
     * @param to The receiver address.
     * @param amount The transfer amount.
     */
    function _update(address from, address to, uint256 amount) internal virtual override {
        // Skip compliance for mints and burns
        if (complianceEnabled && from != address(0) && to != address(0)) {
            _enforceCompliance(from, to);
        }

        super._update(from, to, amount);

        // Emit transfer event for enterprise node indexing
        if (from != address(0) && to != address(0)) {
            emit RestrictedTokenTransfer(from, to, amount);
        }
    }

    /**
     * @dev Performs full compliance validation for a transfer.
     * @param from The sender address.
     * @param to The receiver address.
     */
    function _enforceCompliance(address from, address to) internal {
        IComplianceRegistry registry = IComplianceRegistry(complianceRegistry);

        // 1. Resolve pending credential updates (lazy activation)
        registry.resolveCredential(from, walletJurisdiction[from]);
        registry.resolveCredential(to, walletJurisdiction[to]);

        // 2. Get jurisdictions
        uint256 senderJurisdiction = walletJurisdiction[from];
        uint256 receiverJurisdiction = walletJurisdiction[to];

        // 3. Verify jurisdictions are accepted by this token
        if (!acceptedJurisdictions[senderJurisdiction]) {
            emit ComplianceCheckFailed(from, to, "Sender jurisdiction not accepted");
            revert TransferNotCompliant("Sender jurisdiction not accepted");
        }
        if (!acceptedJurisdictions[receiverJurisdiction]) {
            emit ComplianceCheckFailed(from, to, "Receiver jurisdiction not accepted");
            revert TransferNotCompliant("Receiver jurisdiction not accepted");
        }

        // 4. Validate credentials via ComplianceManager
        bool isValid = IComplianceManager(complianceManager).validateTransfer(
            from,
            to,
            senderJurisdiction,
            receiverJurisdiction,
            requiredLevel
        );

        if (!isValid) {
            emit ComplianceCheckFailed(from, to, "Credential validation failed");
            revert TransferNotCompliant("Credential validation failed");
        }

        // 5. Check matrix compatibility
        bool matrixAllowed = TokenTransferMatrix(matrixContract).matrixAllows(
            senderJurisdiction,
            receiverJurisdiction
        );

        if (!matrixAllowed) {
            emit ComplianceCheckFailed(from, to, "Matrix transfer not allowed");
            revert TransferNotCompliant("Matrix transfer not allowed");
        }
    }

    /**
     * @dev Authorizes contract upgrades — only the owner (issuer) may upgrade.
     *      INVARIANT: complianceEnabled must remain true after upgrade.
     */
    function _authorizeUpgrade(address /* newImplementation */) internal view override onlyOwner {
        // Security invariant: compliance can never be disabled
        if (!complianceEnabled) revert ComplianceCannotBeDisabled();
    }
}
