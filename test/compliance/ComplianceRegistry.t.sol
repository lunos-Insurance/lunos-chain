// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../../contracts/core/ComplianceRegistry.sol";
import "../../contracts/core/ApprovedAttestors.sol";

/**
 * @title ComplianceRegistryTest
 * @notice Unit tests for the ComplianceRegistry contract.
 */
contract ComplianceRegistryTest is Test {
    ComplianceRegistry public registry;
    ApprovedAttestors public attestors;

    address public governance = makeAddr("governance");
    address public attestor1 = makeAddr("attestor1");
    address public wallet1 = makeAddr("wallet1");

    uint256 public constant GLOBAL_DELAY = 10; // blocks
    uint256 public constant EU_JURISDICTION = 1;
    uint256 public constant US_JURISDICTION = 2;

    function setUp() public {
        // Deploy ApprovedAttestors
        ApprovedAttestors attestorsImpl = new ApprovedAttestors();
        bytes memory attestorsInit = abi.encodeWithSelector(
            ApprovedAttestors.initialize.selector,
            governance
        );
        ERC1967Proxy attestorsProxy = new ERC1967Proxy(address(attestorsImpl), attestorsInit);
        attestors = ApprovedAttestors(address(attestorsProxy));

        // Deploy ComplianceRegistry
        ComplianceRegistry registryImpl = new ComplianceRegistry();
        bytes memory registryInit = abi.encodeWithSelector(
            ComplianceRegistry.initialize.selector,
            governance,
            address(attestors),
            GLOBAL_DELAY
        );
        ERC1967Proxy registryProxy = new ERC1967Proxy(address(registryImpl), registryInit);
        registry = ComplianceRegistry(address(registryProxy));

        // Approve attestor1
        vm.prank(governance);
        attestors.addAttestor(attestor1);
    }

    function test_submitCredential_schedulesWithDelay() public {
        uint64 expiry = uint64(block.timestamp + 365 days);

        vm.prank(attestor1);
        registry.submitCredential(wallet1, EU_JURISDICTION, 2, expiry);

        IComplianceRegistry.Credential memory cred = registry.getCredential(wallet1, EU_JURISDICTION);
        assertFalse(cred.active, "Credential should not be active yet");
        assertEq(cred.attestor, attestor1, "Attestor should be recorded");

        IComplianceRegistry.PendingUpdate memory pending = registry.getPendingCredential(wallet1, EU_JURISDICTION);
        assertEq(pending.level, 2, "Pending level mismatch");
        assertEq(pending.expiry, expiry, "Pending expiry mismatch");
        assertTrue(pending.active, "Pending should be active");
        assertEq(pending.effectiveBlock, block.number + GLOBAL_DELAY, "Effective block mismatch");
    }

    function test_resolveCredential_activatesAfterDelay() public {
        uint64 expiry = uint64(block.timestamp + 365 days);

        vm.prank(attestor1);
        registry.submitCredential(wallet1, EU_JURISDICTION, 2, expiry);

        // Roll past the delay
        vm.roll(block.number + GLOBAL_DELAY + 1);

        registry.resolveCredential(wallet1, EU_JURISDICTION);

        IComplianceRegistry.Credential memory cred = registry.getCredential(wallet1, EU_JURISDICTION);
        assertTrue(cred.active, "Credential should be active after resolve");
        assertEq(cred.level, 2, "Level mismatch after resolve");
        assertEq(cred.expiry, expiry, "Expiry mismatch after resolve");
    }

    function test_submitCredential_revertsForNonAttestor() public {
        address notAttestor = makeAddr("notAttestor");

        vm.prank(notAttestor);
        vm.expectRevert(
            abi.encodeWithSelector(ComplianceRegistry.NotApprovedAttestor.selector, notAttestor)
        );
        registry.submitCredential(wallet1, EU_JURISDICTION, 1, uint64(block.timestamp + 30 days));
    }

    function test_scheduleCredentialRevocation() public {
        uint64 expiry = uint64(block.timestamp + 365 days);

        // Submit and activate credential
        vm.prank(attestor1);
        registry.submitCredential(wallet1, EU_JURISDICTION, 2, expiry);
        vm.roll(block.number + GLOBAL_DELAY + 1);
        registry.resolveCredential(wallet1, EU_JURISDICTION);

        // Schedule revocation
        vm.prank(attestor1);
        registry.scheduleCredentialRevocation(wallet1, EU_JURISDICTION);

        // Roll past delay and resolve
        vm.roll(block.number + GLOBAL_DELAY + 1);
        registry.resolveCredential(wallet1, EU_JURISDICTION);

        IComplianceRegistry.Credential memory cred = registry.getCredential(wallet1, EU_JURISDICTION);
        assertFalse(cred.active, "Credential should be inactive after revocation");
    }

    function test_scheduleCredentialUpdate() public {
        uint64 expiry = uint64(block.timestamp + 365 days);

        // Submit and activate initial credential
        vm.prank(attestor1);
        registry.submitCredential(wallet1, EU_JURISDICTION, 1, expiry);
        vm.roll(block.number + GLOBAL_DELAY + 1);
        registry.resolveCredential(wallet1, EU_JURISDICTION);

        // Schedule update to higher level
        uint64 newExpiry = uint64(block.timestamp + 730 days);
        vm.prank(attestor1);
        registry.scheduleCredentialUpdate(wallet1, EU_JURISDICTION, 3, newExpiry);

        // Resolve after delay
        vm.roll(block.number + GLOBAL_DELAY + 1);
        registry.resolveCredential(wallet1, EU_JURISDICTION);

        IComplianceRegistry.Credential memory cred = registry.getCredential(wallet1, EU_JURISDICTION);
        assertEq(cred.level, 3, "Level should be updated");
        assertEq(cred.expiry, newExpiry, "Expiry should be updated");
    }

    function test_globalCredentialDelay_setByGovernance() public {
        uint256 newDelay = 50;

        vm.prank(governance);
        registry.setGlobalCredentialDelay(newDelay);

        assertEq(registry.globalCredentialDelay(), newDelay, "Delay not updated");
    }

    function test_resolveCredential_doesNothingBeforeDelay() public {
        uint64 expiry = uint64(block.timestamp + 365 days);

        vm.prank(attestor1);
        registry.submitCredential(wallet1, EU_JURISDICTION, 2, expiry);

        // Don't roll enough blocks
        vm.roll(block.number + GLOBAL_DELAY - 1);
        registry.resolveCredential(wallet1, EU_JURISDICTION);

        IComplianceRegistry.Credential memory cred = registry.getCredential(wallet1, EU_JURISDICTION);
        assertFalse(cred.active, "Credential should NOT be active before delay expires");
    }
}
