// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../contracts/token/RestrictedToken.sol";
import "../contracts/token/TokenTransferMatrix.sol";
import "../contracts/token/RestrictedTokenFactory.sol";

/**
 * @title DeployToken
 * @notice Foundry deployment script for the token infrastructure.
 * @dev Deploys RestrictedToken and TokenTransferMatrix implementations,
 *      then deploys the RestrictedTokenFactory with UUPS proxy.
 *
 * Usage:
 *   forge script script/DeployToken.s.sol --rpc-url <RPC_URL> --broadcast
 *
 * Required environment variables:
 *   PRIVATE_KEY            - deployer private key
 *   GOVERNANCE_ADDRESS     - governance multisig address
 *   COMPLIANCE_MANAGER     - ComplianceManager proxy address
 *   COMPLIANCE_REGISTRY    - ComplianceRegistry proxy address
 */
contract DeployToken is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address governance = vm.envAddress("GOVERNANCE_ADDRESS");
        address complianceManager = vm.envAddress("COMPLIANCE_MANAGER");
        address complianceRegistry = vm.envAddress("COMPLIANCE_REGISTRY");

        vm.startBroadcast(deployerKey);

        // 1. Deploy implementation contracts
        RestrictedToken tokenImpl = new RestrictedToken();
        console.log("RestrictedToken implementation:", address(tokenImpl));

        TokenTransferMatrix matrixImpl = new TokenTransferMatrix();
        console.log("TokenTransferMatrix implementation:", address(matrixImpl));

        // 2. Deploy RestrictedTokenFactory
        RestrictedTokenFactory factoryImpl = new RestrictedTokenFactory();
        ERC1967Proxy factoryProxy = new ERC1967Proxy(
            address(factoryImpl),
            abi.encodeWithSelector(
                RestrictedTokenFactory.initialize.selector,
                governance,
                address(tokenImpl),
                address(matrixImpl),
                complianceManager,
                complianceRegistry
            )
        );
        console.log("RestrictedTokenFactory:", address(factoryProxy));

        vm.stopBroadcast();
    }
}
