// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "./RestrictedToken.sol";
import "./TokenTransferMatrix.sol";

/**
 * @title RestrictedTokenFactory
 * @notice Factory for deploying new RestrictedToken proxy instances.
 * @dev Deploys a new ERC1967 proxy for each token, pointing to a shared
 *      RestrictedToken implementation. Also deploys a TokenTransferMatrix
 *      for each token. Uses UUPS upgrade pattern.
 *
 * Storage layout:
 *   - address tokenImplementation
 *   - address matrixImplementation
 *   - address complianceManager
 *   - address complianceRegistry
 *   - address[] deployedTokens
 *   - uint256[45] __gap
 */
contract RestrictedTokenFactory is
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    // ───────────────────────── Storage ─────────────────────────────────

    /// @notice Address of the RestrictedToken implementation contract.
    address public tokenImplementation;

    /// @notice Address of the TokenTransferMatrix implementation contract.
    address public matrixImplementation;

    /// @notice Address of the ComplianceManager contract.
    address public complianceManager;

    /// @notice Address of the ComplianceRegistry contract.
    address public complianceRegistry;

    /// @notice List of all deployed token proxy addresses.
    address[] public deployedTokens;

    /// @dev Reserved storage gap for future upgrades.
    uint256[45] private __gap;

    // ───────────────────────── Events ──────────────────────────────────

    /// @notice Emitted when a new restricted token is deployed.
    event RestrictedTokenDeployed(
        address indexed tokenProxy,
        address indexed matrixProxy,
        address indexed issuer,
        string name,
        string symbol
    );

    // ───────────────────────── Errors ──────────────────────────────────

    /// @dev Thrown when an invalid address is provided.
    error InvalidAddress();

    // ───────────────────────── Initializer ─────────────────────────────

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the RestrictedTokenFactory.
     * @param governance The address that will own the factory (governance multisig).
     * @param _tokenImplementation The RestrictedToken implementation address.
     * @param _matrixImplementation The TokenTransferMatrix implementation address.
     * @param _complianceManager The ComplianceManager contract address.
     * @param _complianceRegistry The ComplianceRegistry contract address.
     */
    function initialize(
        address governance,
        address _tokenImplementation,
        address _matrixImplementation,
        address _complianceManager,
        address _complianceRegistry
    ) external initializer {
        if (
            _tokenImplementation == address(0) ||
            _matrixImplementation == address(0) ||
            _complianceManager == address(0) ||
            _complianceRegistry == address(0)
        ) revert InvalidAddress();

        __Ownable_init(governance);

        tokenImplementation = _tokenImplementation;
        matrixImplementation = _matrixImplementation;
        complianceManager = _complianceManager;
        complianceRegistry = _complianceRegistry;
    }

    // ───────────────────────── External Functions ──────────────────────

    /**
     * @notice Deploys a new RestrictedToken with its own TokenTransferMatrix.
     * @dev Creates ERC1967 proxy for both token and matrix. The issuer becomes
     *      the owner of the token and matrix contracts.
     * @param name The token name.
     * @param symbol The token symbol.
     * @param issuer The address that will control the token (issuer).
     * @param requiredLevel_ The minimum compliance level for transfers.
     * @param tokenDelay_ The timelock delay (in blocks) for matrix updates.
     * @return tokenProxy The address of the deployed token proxy.
     * @return matrixProxy The address of the deployed matrix proxy.
     */
    function deployToken(
        string memory name,
        string memory symbol,
        address issuer,
        uint8 requiredLevel_,
        uint256 tokenDelay_
    ) external returns (address tokenProxy, address matrixProxy) {
        // Deploy matrix proxy
        bytes memory matrixInitData = abi.encodeWithSelector(
            TokenTransferMatrix.initialize.selector,
            issuer,
            tokenDelay_
        );
        matrixProxy = address(new ERC1967Proxy(matrixImplementation, matrixInitData));

        // Deploy token proxy
        bytes memory tokenInitData = abi.encodeWithSelector(
            RestrictedToken.initialize.selector,
            name,
            symbol,
            issuer,
            complianceManager,
            complianceRegistry,
            matrixProxy,
            requiredLevel_
        );
        tokenProxy = address(new ERC1967Proxy(tokenImplementation, tokenInitData));

        deployedTokens.push(tokenProxy);

        emit RestrictedTokenDeployed(tokenProxy, matrixProxy, issuer, name, symbol);
    }

    /**
     * @notice Returns the total number of deployed tokens.
     * @return count The number of deployed tokens.
     */
    function deployedTokenCount() external view returns (uint256 count) {
        return deployedTokens.length;
    }

    // ───────────────────────── Internal ────────────────────────────────

    /**
     * @dev Authorizes contract upgrades — only the owner (governance) may upgrade.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
