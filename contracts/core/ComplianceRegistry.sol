// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../interfaces/IComplianceRegistry.sol";
import "../interfaces/IAttestor.sol";

/**
 * @title ComplianceRegistry
 * @notice Stores wallet compliance credentials indexed by (wallet, jurisdiction).
 * @dev Credential updates are timelocked: effectiveBlock = block.number + globalCredentialDelay.
 *      Only approved attestors may submit credentials. Pending updates activate lazily
 *      during reads. Uses UUPS upgrade pattern.
 *
 * Storage layout:
 *   - mapping(address => mapping(uint256 => Credential)) _credentials
 *   - uint256 globalCredentialDelay
 *   - IAttestor approvedAttestors
 *   - uint256[48] __gap
 */
contract ComplianceRegistry is
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    IComplianceRegistry
{
    // ───────────────────────── Storage ─────────────────────────────────

    /// @notice Credential storage: wallet => jurisdiction => Credential.
    mapping(address => mapping(uint256 => Credential)) private _credentials;

    /// @notice Global delay (in blocks) before credential updates become active.
    uint256 public globalCredentialDelay;

    /// @notice Reference to the approved attestors registry.
    IAttestor public approvedAttestors;

    /// @dev Reserved storage gap for future upgrades.
    uint256[48] private __gap;

    // ───────────────────────── Errors ──────────────────────────────────

    /// @dev Thrown when the caller is not an approved attestor.
    error NotApprovedAttestor(address caller);

    /// @dev Thrown when the caller is not the attestor of the credential or governance.
    error UnauthorizedRevocation(address caller);

    /// @dev Thrown when an invalid address is provided.
    error InvalidAddress();

    // ───────────────────────── Modifiers ───────────────────────────────

    /// @notice Restricts function access to approved attestors only.
    modifier onlyAttestor() {
        if (!approvedAttestors.isAttestor(msg.sender)) {
            revert NotApprovedAttestor(msg.sender);
        }
        _;
    }

    // ───────────────────────── Initializer ─────────────────────────────

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the ComplianceRegistry.
     * @param governance The address that will own the contract (governance multisig).
     * @param _approvedAttestors The address of the ApprovedAttestors contract.
     * @param _globalDelay The initial global credential delay in blocks.
     */
    function initialize(
        address governance,
        address _approvedAttestors,
        uint256 _globalDelay
    ) external initializer {
        if (_approvedAttestors == address(0)) revert InvalidAddress();

        __Ownable_init(governance);

        approvedAttestors = IAttestor(_approvedAttestors);
        globalCredentialDelay = _globalDelay;
    }

    // ───────────────────────── External Functions ──────────────────────

    /// @inheritdoc IComplianceRegistry
    function submitCredential(
        address wallet,
        uint256 jurisdiction,
        uint8 level,
        uint64 expiry
    ) external onlyAttestor {
        Credential storage cred = _credentials[wallet][jurisdiction];

        uint256 effectiveBlock = block.number + globalCredentialDelay;

        cred.pending = PendingUpdate({
            level: level,
            expiry: expiry,
            active: true,
            effectiveBlock: effectiveBlock
        });
        cred.attestor = msg.sender;

        emit CredentialScheduled(wallet, jurisdiction, level, expiry, effectiveBlock);
    }

    /// @inheritdoc IComplianceRegistry
    function scheduleCredentialUpdate(
        address wallet,
        uint256 jurisdiction,
        uint8 level,
        uint64 expiry
    ) external onlyAttestor {
        Credential storage cred = _credentials[wallet][jurisdiction];

        uint256 effectiveBlock = block.number + globalCredentialDelay;

        cred.pending = PendingUpdate({
            level: level,
            expiry: expiry,
            active: true,
            effectiveBlock: effectiveBlock
        });

        emit CredentialScheduled(wallet, jurisdiction, level, expiry, effectiveBlock);
    }

    /// @inheritdoc IComplianceRegistry
    function scheduleCredentialRevocation(
        address wallet,
        uint256 jurisdiction
    ) external {
        Credential storage cred = _credentials[wallet][jurisdiction];

        // Only the original attestor or governance (owner) may revoke
        if (msg.sender != cred.attestor && msg.sender != owner()) {
            revert UnauthorizedRevocation(msg.sender);
        }

        uint256 effectiveBlock = block.number + globalCredentialDelay;

        cred.pending = PendingUpdate({
            level: 0,
            expiry: 0,
            active: false,
            effectiveBlock: effectiveBlock
        });

        emit CredentialRevoked(wallet, jurisdiction);
    }

    /// @inheritdoc IComplianceRegistry
    function resolveCredential(
        address wallet,
        uint256 jurisdiction
    ) external {
        _resolveCredential(wallet, jurisdiction);
    }

    /// @inheritdoc IComplianceRegistry
    function getCredential(
        address wallet,
        uint256 jurisdiction
    ) external view returns (Credential memory credential) {
        return _credentials[wallet][jurisdiction];
    }

    /// @inheritdoc IComplianceRegistry
    function getPendingCredential(
        address wallet,
        uint256 jurisdiction
    ) external view returns (PendingUpdate memory pending) {
        return _credentials[wallet][jurisdiction].pending;
    }

    // ───────────────────────── Governance Functions ────────────────────

    /**
     * @notice Updates the global credential delay.
     * @dev Only governance (owner) may call this.
     * @param newDelay The new global delay in blocks.
     */
    function setGlobalCredentialDelay(uint256 newDelay) external onlyOwner {
        globalCredentialDelay = newDelay;
        // TODO: emit event for delay change
    }

    /**
     * @notice Updates the approved attestors contract reference.
     * @dev Only governance (owner) may call this.
     * @param _approvedAttestors The new ApprovedAttestors contract address.
     */
    function setApprovedAttestors(address _approvedAttestors) external onlyOwner {
        if (_approvedAttestors == address(0)) revert InvalidAddress();
        approvedAttestors = IAttestor(_approvedAttestors);
    }

    // ───────────────────────── Internal Functions ──────────────────────

    /**
     * @dev Resolves pending credential updates if the effective block has passed.
     *      This implements lazy activation — pending updates are applied on read.
     * @param wallet The wallet address.
     * @param jurisdiction The jurisdiction identifier.
     */
    function _resolveCredential(address wallet, uint256 jurisdiction) internal {
        Credential storage cred = _credentials[wallet][jurisdiction];
        PendingUpdate storage pending = cred.pending;

        if (pending.effectiveBlock != 0 && block.number >= pending.effectiveBlock) {
            cred.level = pending.level;
            cred.expiry = pending.expiry;
            cred.active = pending.active;

            // Clear pending update
            delete cred.pending;

            emit CredentialActivated(wallet, jurisdiction, cred.level, cred.expiry);
        }
    }

    /**
     * @dev Authorizes contract upgrades — only the owner (governance) may upgrade.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
