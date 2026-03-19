// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../../contracts/token/RestrictedToken.sol";
import "../../contracts/token/TokenTransferMatrix.sol";
import "../../contracts/core/ComplianceManager.sol";
import "../../contracts/core/ComplianceRegistry.sol";
import "../../contracts/core/ApprovedAttestors.sol";
import "../../contracts/core/JurisdictionRegistry.sol";

/**
 * @title RestrictedTokenTest
 * @notice Unit tests for the RestrictedToken contract.
 */
contract RestrictedTokenTest is Test {
    RestrictedToken public token;
    TokenTransferMatrix public matrix;
    ComplianceManager public manager;
    ComplianceRegistry public registry;
    ApprovedAttestors public attestors;
    JurisdictionRegistry public jurisdictions;

    address public governance = makeAddr("governance");
    address public issuer = makeAddr("issuer");
    address public attestor1 = makeAddr("attestor1");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 public constant GLOBAL_DELAY = 10;
    uint256 public constant TOKEN_DELAY = 5;
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

        // Deploy TokenTransferMatrix
        TokenTransferMatrix matrixImpl = new TokenTransferMatrix();
        ERC1967Proxy matrixProxy = new ERC1967Proxy(
            address(matrixImpl),
            abi.encodeWithSelector(
                TokenTransferMatrix.initialize.selector,
                issuer,
                TOKEN_DELAY
            )
        );
        matrix = TokenTransferMatrix(address(matrixProxy));

        // Deploy RestrictedToken
        RestrictedToken tokenImpl = new RestrictedToken();
        ERC1967Proxy tokenProxy = new ERC1967Proxy(
            address(tokenImpl),
            abi.encodeWithSelector(
                RestrictedToken.initialize.selector,
                "Restricted EUR",
                "rEUR",
                issuer,
                address(manager),
                address(registry),
                address(matrix),
                uint8(1) // Retail level
            )
        );
        token = RestrictedToken(address(tokenProxy));

        // Setup: add jurisdictions, attestor, and matrix
        vm.startPrank(governance);
        jurisdictions.addJurisdiction(EU);
        jurisdictions.addJurisdiction(US);
        attestors.addAttestor(attestor1);
        vm.stopPrank();

        // Accept EU jurisdiction for this token and set matrix
        vm.startPrank(issuer);
        token.setAcceptedJurisdiction(EU, true);
        matrix.scheduleMatrixUpdate(EU, EU, true);
        vm.stopPrank();

        // Activate matrix
        vm.roll(block.number + TOKEN_DELAY + 1);
        matrix.resolveMatrixUpdate(EU, EU);
    }

    function _setupCompliantWallet(address wallet, uint256 jurisdiction, uint8 level) internal {
        uint64 expiry = uint64(block.timestamp + 365 days);

        vm.prank(attestor1);
        registry.submitCredential(wallet, jurisdiction, level, expiry);
        vm.roll(block.number + GLOBAL_DELAY + 1);
        registry.resolveCredential(wallet, jurisdiction);

        vm.prank(wallet);
        token.setWalletJurisdiction(jurisdiction);
    }

    function test_mint() public {
        vm.prank(issuer);
        token.mint(alice, 1000e18);

        assertEq(token.balanceOf(alice), 1000e18, "Mint balance mismatch");
    }

    function test_burn() public {
        vm.prank(issuer);
        token.mint(alice, 1000e18);

        vm.prank(issuer);
        token.burn(alice, 500e18);

        assertEq(token.balanceOf(alice), 500e18, "Burn balance mismatch");
    }

    function test_transfer_compliantWallets() public {
        _setupCompliantWallet(alice, EU, 2);
        _setupCompliantWallet(bob, EU, 2);

        vm.prank(issuer);
        token.mint(alice, 1000e18);

        vm.prank(alice);
        token.transfer(bob, 500e18);

        assertEq(token.balanceOf(alice), 500e18, "Alice balance mismatch");
        assertEq(token.balanceOf(bob), 500e18, "Bob balance mismatch");
    }

    function test_transfer_revertsForNonCompliantSender() public {
        // Bob is compliant but Alice has no credentials
        _setupCompliantWallet(bob, EU, 2);

        vm.prank(issuer);
        token.mint(alice, 1000e18);

        vm.prank(alice);
        token.setWalletJurisdiction(EU);

        vm.prank(alice);
        vm.expectRevert();
        token.transfer(bob, 500e18);
    }

    function test_transfer_revertsForMatrixIncompatibility() public {
        // Setup wallets in different jurisdictions
        _setupCompliantWallet(alice, EU, 2);

        // Setup bob in US jurisdiction
        uint64 expiry = uint64(block.timestamp + 365 days);
        vm.prank(attestor1);
        registry.submitCredential(bob, US, 2, expiry);
        vm.roll(block.number + GLOBAL_DELAY + 1);
        registry.resolveCredential(bob, US);

        vm.prank(bob);
        token.setWalletJurisdiction(US);

        // Accept US but don't allow EU->US in matrix
        vm.prank(issuer);
        token.setAcceptedJurisdiction(US, true);

        vm.prank(issuer);
        token.mint(alice, 1000e18);

        vm.prank(alice);
        vm.expectRevert();
        token.transfer(bob, 500e18);
    }

    function test_complianceEnabled_cannotBeDisabled() public {
        assertTrue(token.complianceEnabled(), "Compliance should be enabled");
        // TODO: verify compliance cannot be disabled via upgrade
    }

    function test_setRequiredLevel() public {
        vm.prank(issuer);
        token.setRequiredLevel(3);

        assertEq(token.requiredLevel(), 3, "Required level not updated");
    }

    function test_setAcceptedJurisdiction() public {
        vm.prank(issuer);
        token.setAcceptedJurisdiction(US, true);

        assertTrue(token.acceptedJurisdictions(US), "US should be accepted");
    }
}
