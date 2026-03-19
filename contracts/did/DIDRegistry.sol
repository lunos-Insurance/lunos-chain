// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title DIDRegistry
 * @notice Placeholder for optional decentralized identity anchor.
 * @dev Future module — stores wallet-to-DID hash mappings. No PII stored on-chain.
 *      This is a minimal placeholder for future upgrades.
 *
 * Storage layout:
 *   - mapping(address => bytes32) _didHashes
 *   - uint256[50] __gap
 */
contract DIDRegistry is
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    // ───────────────────────── Storage ─────────────────────────────────

    /// @notice Maps wallet address to DID hash. No PII.
    mapping(address => bytes32) private _didHashes;

    /// @dev Reserved storage gap for future upgrades.
    uint256[50] private __gap;

    // ───────────────────────── Events ──────────────────────────────────

    /// @notice Emitted when a DID hash is set for a wallet.
    event DIDHashSet(address indexed wallet, bytes32 didHash);

    // ───────────────────────── Initializer ─────────────────────────────

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the DIDRegistry.
     * @param governance The address that will own the registry (governance multisig).
     */
    function initialize(address governance) external initializer {
        __Ownable_init(governance);
    }

    // ───────────────────────── External Functions ──────────────────────

    /**
     * @notice Sets the DID hash for the caller's wallet.
     * @dev No PII is stored — only a hash of the DID document.
     * @param didHash The keccak256 hash of the DID document.
     */
    function setDIDHash(bytes32 didHash) external {
        // TODO: implement access control and validation
        _didHashes[msg.sender] = didHash;
        emit DIDHashSet(msg.sender, didHash);
    }

    /**
     * @notice Returns the DID hash for a wallet.
     * @param wallet The wallet address.
     * @return didHash The DID hash.
     */
    function getDIDHash(address wallet) external view returns (bytes32 didHash) {
        return _didHashes[wallet];
    }

    // ───────────────────────── Internal ────────────────────────────────

    /**
     * @dev Authorizes contract upgrades — only the owner (governance) may upgrade.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
