// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../../contracts/token/TokenTransferMatrix.sol";

/**
 * @title TokenTransferMatrixTest
 * @notice Unit tests for the TokenTransferMatrix contract.
 */
contract TokenTransferMatrixTest is Test {
    TokenTransferMatrix public matrix;

    address public issuer = makeAddr("issuer");

    uint256 public constant TOKEN_DELAY = 5;
    uint256 public constant EU = 1;
    uint256 public constant US = 2;
    uint256 public constant UAE = 3;

    function setUp() public {
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
    }

    function test_scheduleMatrixUpdate() public {
        vm.prank(issuer);
        matrix.scheduleMatrixUpdate(EU, US, true);

        TokenTransferMatrix.PendingMatrixUpdate memory pending =
            matrix.getPendingMatrixUpdate(EU, US);

        assertTrue(pending.exists, "Pending update should exist");
        assertTrue(pending.allowed, "Pending should allow");
        assertEq(pending.effectiveBlock, block.number + TOKEN_DELAY, "Effective block mismatch");
    }

    function test_resolveMatrixUpdate_activatesAfterDelay() public {
        vm.prank(issuer);
        matrix.scheduleMatrixUpdate(EU, US, true);

        // Roll past delay
        vm.roll(block.number + TOKEN_DELAY + 1);
        matrix.resolveMatrixUpdate(EU, US);

        assertTrue(matrix.matrixAllows(EU, US), "Matrix should allow EU->US");
    }

    function test_resolveMatrixUpdate_doesNothingBeforeDelay() public {
        vm.prank(issuer);
        matrix.scheduleMatrixUpdate(EU, US, true);

        // Roll but not past delay
        vm.roll(block.number + TOKEN_DELAY - 1);

        // This should not revert but also not activate
        // The pending update still exists
        TokenTransferMatrix.PendingMatrixUpdate memory pending =
            matrix.getPendingMatrixUpdate(EU, US);
        assertTrue(pending.exists, "Pending should still exist");
        assertFalse(matrix.matrixAllows(EU, US), "Matrix should NOT allow before delay");
    }

    function test_matrixAllows_defaultFalse() public view {
        assertFalse(matrix.matrixAllows(EU, US), "Default should be false");
    }

    function test_scheduleMatrixUpdate_onlyIssuer() public {
        address notIssuer = makeAddr("notIssuer");

        vm.prank(notIssuer);
        vm.expectRevert();
        matrix.scheduleMatrixUpdate(EU, US, true);
    }

    function test_setTokenDelay() public {
        vm.prank(issuer);
        matrix.setTokenDelay(20);

        assertEq(matrix.tokenDelay(), 20, "Token delay not updated");
    }

    function test_matrixUpdate_disableRoute() public {
        // Enable route
        vm.prank(issuer);
        matrix.scheduleMatrixUpdate(EU, EU, true);
        vm.roll(block.number + TOKEN_DELAY + 1);
        matrix.resolveMatrixUpdate(EU, EU);
        assertTrue(matrix.matrixAllows(EU, EU), "Route should be enabled");

        // Disable route
        vm.prank(issuer);
        matrix.scheduleMatrixUpdate(EU, EU, false);
        vm.roll(block.number + TOKEN_DELAY + 1);
        matrix.resolveMatrixUpdate(EU, EU);
        assertFalse(matrix.matrixAllows(EU, EU), "Route should be disabled");
    }
}
