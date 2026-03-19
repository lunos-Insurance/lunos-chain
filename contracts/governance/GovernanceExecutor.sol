// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title GovernanceExecutor
 * @notice Wrapper contract that enables multisig governance execution.
 * @dev Allows the governance multisig to execute arbitrary calls to system
 *      contracts (registry updates, attestor updates, compliance upgrades).
 *      Off-chain signing, on-chain execution. Uses UUPS upgrade pattern.
 *
 * Storage layout:
 *   - uint256[50] __gap
 */
contract GovernanceExecutor is
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    // ───────────────────────── Storage ─────────────────────────────────

    /// @dev Reserved storage gap for future upgrades.
    uint256[50] private __gap;

    // ───────────────────────── Events ──────────────────────────────────

    /// @notice Emitted when a governance action is executed.
    event GovernanceActionExecuted(
        address indexed target,
        bytes data,
        uint256 value,
        bool success
    );

    /// @notice Emitted when a batch of governance actions is executed.
    event GovernanceBatchExecuted(uint256 actionCount);

    // ───────────────────────── Errors ──────────────────────────────────

    /// @dev Thrown when a governance action execution fails.
    error ExecutionFailed(address target, bytes data);

    /// @dev Thrown when array lengths don't match in batch execution.
    error ArrayLengthMismatch();

    // ───────────────────────── Initializer ─────────────────────────────

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the GovernanceExecutor.
     * @param governance The address that will own the executor (governance multisig).
     */
    function initialize(address governance) external initializer {
        __Ownable_init(governance);
    }

    // ───────────────────────── External Functions ──────────────────────

    /**
     * @notice Executes a single governance action.
     * @dev Only the governance multisig (owner) may call this.
     * @param target The address of the contract to call.
     * @param data The calldata to send.
     * @param value The ETH value to send with the call.
     * @return result The return data from the call.
     */
    function execute(
        address target,
        bytes calldata data,
        uint256 value
    ) external payable onlyOwner returns (bytes memory result) {
        bool success;
        (success, result) = target.call{value: value}(data);

        if (!success) revert ExecutionFailed(target, data);

        emit GovernanceActionExecuted(target, data, value, success);
    }

    /**
     * @notice Executes a batch of governance actions.
     * @dev Only the governance multisig (owner) may call this. All actions must
     *      succeed or the entire batch reverts.
     * @param targets The addresses of the contracts to call.
     * @param dataArray The calldata for each call.
     * @param values The ETH values for each call.
     */
    function executeBatch(
        address[] calldata targets,
        bytes[] calldata dataArray,
        uint256[] calldata values
    ) external payable onlyOwner {
        if (targets.length != dataArray.length || targets.length != values.length) {
            revert ArrayLengthMismatch();
        }

        for (uint256 i = 0; i < targets.length; i++) {
            (bool success, ) = targets[i].call{value: values[i]}(dataArray[i]);
            if (!success) revert ExecutionFailed(targets[i], dataArray[i]);

            emit GovernanceActionExecuted(targets[i], dataArray[i], values[i], success);
        }

        emit GovernanceBatchExecuted(targets.length);
    }

    // ───────────────────────── Internal ────────────────────────────────

    /**
     * @dev Authorizes contract upgrades — only the owner (governance) may upgrade.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev Allow the contract to receive ETH for governance operations.
     */
    receive() external payable {}
}
