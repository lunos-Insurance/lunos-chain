// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../contracts/core/JurisdictionRegistry.sol";
import "../contracts/core/ApprovedAttestors.sol";
import "../contracts/core/ComplianceRegistry.sol";
import "../contracts/core/ComplianceManager.sol";
import "../contracts/governance/GovernanceExecutor.sol";

/**
 * @title DeployCore
 * @notice Foundry deployment script for core compliance infrastructure.
 * @dev Deploys: GovernanceExecutor, JurisdictionRegistry, ApprovedAttestors,
 *      ComplianceRegistry, and ComplianceManager with UUPS proxies.
 *
 * Usage:
 *   forge script script/DeployCore.s.sol --rpc-url <RPC_URL> --broadcast
 */
contract DeployCore is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address governance = vm.envAddress("GOVERNANCE_ADDRESS");
        uint256 globalDelay = vm.envOr("GLOBAL_DELAY", uint256(100));

        vm.startBroadcast(deployerKey);

        // 1. Deploy GovernanceExecutor
        GovernanceExecutor govImpl = new GovernanceExecutor();
        ERC1967Proxy govProxy = new ERC1967Proxy(
            address(govImpl),
            abi.encodeWithSelector(GovernanceExecutor.initialize.selector, governance)
        );
        console.log("GovernanceExecutor:", address(govProxy));

        // 2. Deploy JurisdictionRegistry
        JurisdictionRegistry jurisdictionImpl = new JurisdictionRegistry();
        ERC1967Proxy jurisdictionProxy = new ERC1967Proxy(
            address(jurisdictionImpl),
            abi.encodeWithSelector(JurisdictionRegistry.initialize.selector, address(govProxy))
        );
        console.log("JurisdictionRegistry:", address(jurisdictionProxy));

        // 3. Deploy ApprovedAttestors
        ApprovedAttestors attestorsImpl = new ApprovedAttestors();
        ERC1967Proxy attestorsProxy = new ERC1967Proxy(
            address(attestorsImpl),
            abi.encodeWithSelector(ApprovedAttestors.initialize.selector, address(govProxy))
        );
        console.log("ApprovedAttestors:", address(attestorsProxy));

        // 4. Deploy ComplianceRegistry
        ComplianceRegistry registryImpl = new ComplianceRegistry();
        ERC1967Proxy registryProxy = new ERC1967Proxy(
            address(registryImpl),
            abi.encodeWithSelector(
                ComplianceRegistry.initialize.selector,
                address(govProxy),
                address(attestorsProxy),
                globalDelay
            )
        );
        console.log("ComplianceRegistry:", address(registryProxy));

        // 5. Deploy ComplianceManager
        ComplianceManager managerImpl = new ComplianceManager();
        ERC1967Proxy managerProxy = new ERC1967Proxy(
            address(managerImpl),
            abi.encodeWithSelector(
                ComplianceManager.initialize.selector,
                address(govProxy),
                address(registryProxy),
                address(jurisdictionProxy)
            )
        );
        console.log("ComplianceManager:", address(managerProxy));

        vm.stopBroadcast();
    }
}
