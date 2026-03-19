// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../../contracts/core/ComplianceManager.sol";
import "../../contracts/core/ComplianceRegistry.sol";
import "../../contracts/core/ApprovedAttestors.sol";
import "../../contracts/core/JurisdictionRegistry.sol";

/**
 * @title ComplianceManagerTest
 * @notice Unit tests for the ComplianceManager contract.
 */
contract ComplianceManagerTest is Test {
    ComplianceManager public manager;
    ComplianceRegistry public registry;
    ApprovedAttestors public attestors;
    JurisdictionRegistry public jurisdictions;

    address public governance = makeAddr("governance");
    address public attestor1 = makeAddr("attestor1");
    address public sender = makeAddr("sender");
    address public receiver = makeAddr("receiver");

    uint256 public constant GLOBAL_DELAY = 10;
    uint256 public constant EU = 1;
    uint256 public constant US = 2;

    function setUp() public {
        // Deploy JurisdictionRegistry
        JurisdictionRegistry jurisdictionsImpl = new JurisdictionRegistry();
        ERC1967Proxy jurisdictionsProxy = new ERC1967Proxy(
            address(jurisdictionsImpl),
            abi.encodeWithSelector(JurisdictionRegistry.initialize.selector, governance)
        );
        jurisdictions = JurisdictionRegistry(address(jurisdictionsProxy));

        // Deploy ApprovedAttestors
        ApprovedAttestors attestorsImpl = new ApprovedAttestors();
        ERC1967Proxy attestorsProxy = new ERC1967Proxy(
            address(attestorsImpl),
            abi.encodeWithSelector(ApprovedAttestors.initialize.selector, governance)
        );
        attestors = ApprovedAttestors(address(attestorsProxy));

        // Deploy ComplianceRegistry
        ComplianceRegistry registryImpl = new ComplianceRegistry();
        ERC1967Proxy registryProxy = new ERC1967Proxy(
            address(registryImpl),
            abi.encodeWithSelector(
                ComplianceRegistry.initialize.selector,
                governance,
                address(attestors),
                GLOBAL_DELAY
            )
        );
        registry = ComplianceRegistry(address(registryProxy));

        // Deploy ComplianceManager
        ComplianceManager managerImpl = new ComplianceManager();
        ERC1967Proxy managerProxy = new ERC1967Proxy(
            address(managerImpl),
            abi.encodeWithSelector(
                ComplianceManager.initialize.selector,
                governance,
                address(registry),
                address(jurisdictions)
            )
        );
        manager = ComplianceManager(address(managerProxy));

        // Setup: add jurisdictions and attestor
        vm.startPrank(governance);
        jurisdictions.addJurisdiction(EU);
        jurisdictions.addJurisdiction(US);
        attestors.addAttestor(attestor1);
        vm.stopPrank();
    }

    function _issueAndActivateCredential(
        address wallet,
        uint256 jurisdiction,
        uint8 level,
        uint64 expiry
    ) internal {
        vm.prank(attestor1);
        registry.submitCredential(wallet, jurisdiction, level, expiry);
        vm.roll(block.number + GLOBAL_DELAY + 1);
        registry.resolveCredential(wallet, jurisdiction);
    }

    function test_validateTransfer_validCredentials() public {
        uint64 expiry = uint64(block.timestamp + 365 days);

        _issueAndActivateCredential(sender, EU, 2, expiry);
        _issueAndActivateCredential(receiver, EU, 2, expiry);

        bool result = manager.validateTransfer(sender, receiver, EU, EU, 1);
        assertTrue(result, "Valid transfer should pass");
    }

    function test_validateTransfer_expiredCredential() public {
        uint64 expiry = uint64(block.timestamp + 1); // Expires very soon

        _issueAndActivateCredential(sender, EU, 2, expiry);
        _issueAndActivateCredential(receiver, EU, 2, expiry);

        // Warp past expiry
        vm.warp(block.timestamp + 2);

        bool result = manager.validateTransfer(sender, receiver, EU, EU, 1);
        assertFalse(result, "Expired credential should fail");
    }

    function test_validateTransfer_insufficientLevel() public {
        uint64 expiry = uint64(block.timestamp + 365 days);

        _issueAndActivateCredential(sender, EU, 1, expiry); // Retail level
        _issueAndActivateCredential(receiver, EU, 1, expiry);

        // Require Accredited (level 2)
        bool result = manager.validateTransfer(sender, receiver, EU, EU, 2);
        assertFalse(result, "Insufficient level should fail");
    }

    function test_validateTransfer_missingCredential() public {
        // No credentials issued
        bool result = manager.validateTransfer(sender, receiver, EU, EU, 1);
        assertFalse(result, "Missing credential should fail");
    }

    function test_validateTransfer_invalidJurisdiction() public {
        uint64 expiry = uint64(block.timestamp + 365 days);

        _issueAndActivateCredential(sender, EU, 2, expiry);
        _issueAndActivateCredential(receiver, EU, 2, expiry);

        // Use unregistered jurisdiction 99
        bool result = manager.validateTransfer(sender, receiver, 99, EU, 1);
        assertFalse(result, "Invalid jurisdiction should fail");
    }

    function test_validateTransfer_levelHierarchy() public {
        uint64 expiry = uint64(block.timestamp + 365 days);

        // Institutional (3) satisfies Accredited (2) requirement
        _issueAndActivateCredential(sender, EU, 3, expiry);
        _issueAndActivateCredential(receiver, EU, 3, expiry);

        bool result = manager.validateTransfer(sender, receiver, EU, EU, 2);
        assertTrue(result, "Institutional should satisfy Accredited requirement");
    }
}
