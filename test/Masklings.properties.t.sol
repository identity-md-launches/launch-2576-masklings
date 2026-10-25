// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Masklings} from "../src/Masklings.sol";

/// @dev Properties that complement the basic ERC-20 tests with repeated actions and boundary transitions.
/// forge-config: default.fuzz.runs = 1000
contract MasklingsPropertiesTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    Masklings private token;
    address private alice;
    address private bob;
    address private spender;

    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        token = new Masklings();
        alice = makeAddr("property holder");
        bob = makeAddr("property recipient");
        spender = makeAddr("property spender");
    }

    function test_oneSmallestUnitCanMakeRoundTrip() public {
        assertTrue(token.transfer(alice, 1));
        _roundTrip(1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), 0);
    }

    function testFuzz_roundTripsPreserveBalancesAndApprovals(
        uint256 aliceAllocation,
        uint256 bobAllocation,
        uint256 amount,
        uint256 approved
    ) public {
        aliceAllocation = bound(aliceAllocation, 0, SUPPLY);
        bobAllocation = bound(bobAllocation, 0, SUPPLY - aliceAllocation);
        amount = bound(amount, 0, aliceAllocation);
        assertTrue(token.transfer(alice, aliceAllocation));
        assertTrue(token.transfer(bob, bobAllocation));
        vm.prank(alice);
        assertTrue(token.approve(spender, approved));
        for (uint256 i; i < 3; ++i) {
            _roundTrip(amount);
        }
        assertEq(token.allowance(alice, spender), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY - aliceAllocation - bobAllocation);
        assertEq(token.balanceOf(spender), 0);
    }

    function testFuzz_splittingDelegatedTransferHasSameEffect(uint256 amount, uint256 first, uint256 approved) public {
        amount = bound(amount, 0, SUPPLY);
        first = bound(first, 0, amount);
        approved = bound(approved, amount, type(uint256).max);
        Masklings singleTransfer = new Masklings();
        assertTrue(token.approve(spender, approved));
        assertTrue(singleTransfer.approve(spender, approved));

        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), bob, first));
        assertTrue(token.transferFrom(address(this), bob, amount - first));
        assertTrue(singleTransfer.transferFrom(address(this), bob, amount));
        vm.stopPrank();

        assertEq(token.balanceOf(address(this)), singleTransfer.balanceOf(address(this)));
        assertEq(token.balanceOf(bob), singleTransfer.balanceOf(bob));
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.allowance(address(this), spender), singleTransfer.allowance(address(this), spender));
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(singleTransfer.totalSupply(), SUPPLY);
    }

    function testFuzz_returnedTokensDoNotRestoreSpentAllowance(uint256 amount) public {
        amount = bound(amount, 1, SUPPLY);
        assertTrue(token.transfer(alice, amount));
        vm.prank(alice);
        assertTrue(token.approve(spender, amount));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, amount));
        vm.prank(bob);
        assertTrue(token.transfer(alice, amount));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);

        // Only a fresh approval authorizes another spend.
        vm.prank(alice);
        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), amount - 1);
        assertEq(token.balanceOf(bob), 1);
    }

    function testFuzz_infiniteApprovalCanBecomeFinite(uint256 approved) public {
        approved = bound(approved, 1, SUPPLY - 1);
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);

        assertTrue(token.approve(spender, approved));
        assertEq(token.allowance(address(this), spender), approved);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, approved));
        assertEq(token.allowance(address(this), spender), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - approved - 1);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), approved);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_infiniteApprovalCanBeRevokedAfterUse() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertTrue(token.approve(spender, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.balanceOf(alice), 1);
    }

    function test_maximumMinusOneApprovalIsFinite() public {
        assertTrue(token.approve(spender, type(uint256).max - 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max - 2);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_approvalOverwriteIsIdempotentAndIsolated(uint256 initial, uint256 replacement) public {
        assertTrue(token.approve(spender, initial));
        assertTrue(token.approve(bob, initial));
        vm.prank(alice);
        assertTrue(token.approve(spender, initial));
        assertTrue(token.approve(spender, replacement));
        assertTrue(token.approve(spender, replacement));
        assertEq(token.allowance(address(this), spender), replacement);
        assertEq(token.allowance(address(this), bob), initial);
        assertEq(token.allowance(alice, spender), initial);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_balanceFailurePreservesApprovalAndCanBeRetriedAfterFunding(
        uint256 balance,
        uint256 attempted,
        bool infinite
    ) public {
        balance = bound(balance, 0, SUPPLY - 1);
        attempted = bound(attempted, balance + 1, SUPPLY);
        uint256 approved = infinite ? type(uint256).max : attempted;
        assertTrue(token.transfer(alice, balance));
        vm.prank(alice);
        assertTrue(token.approve(spender, approved));

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, attempted)
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, attempted);
        assertEq(token.allowance(alice, spender), approved);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);

        assertTrue(token.transfer(alice, attempted - balance));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, attempted));
        assertEq(token.allowance(alice, spender), infinite ? type(uint256).max : 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), attempted);
        assertEq(token.balanceOf(address(this)), SUPPLY - attempted);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_zeroRecipientFailurePreservesAllState(uint256 amount, uint256 approved) public {
        amount = bound(amount, 0, SUPPLY);
        approved = bound(approved, amount, type(uint256).max);
        assertTrue(token.approve(spender, approved));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), amount);
        assertEq(token.allowance(address(this), spender), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_zeroDelegatedTransferPreservesExistingApproval(uint256 approved) public {
        assertTrue(token.approve(spender, approved));
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 0));
        assertEq(token.allowance(address(this), spender), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maximumDelegatedTransferFailsForBalanceAndKeepsInfiniteApproval() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, type(uint256).max);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_selfApprovalAndFullSupplyDelegatedSelfTransfer() public {
        assertTrue(token.transfer(alice, SUPPLY));
        vm.prank(alice);
        assertTrue(token.approve(alice, SUPPLY));
        vm.prank(alice);
        assertTrue(token.transferFrom(alice, alice, SUPPLY));
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.allowance(alice, alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transferFrom(alice, bob, 1);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_holderAsTransactionOriginDoesNotAuthorizeSpender() public {
        assertTrue(token.transfer(alice, SUPPLY));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender, alice);
        token.transferFrom(alice, bob, 1);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.allowance(alice, spender), 0);
    }

    function test_zeroSpenderIsInvalidEvenForZeroApproval() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_zeroSourceCannotMintThroughZeroTransferFrom() public {
        // ERC-20 requires rejection; the exact error depends on which validation runs first.
        vm.expectRevert();
        vm.prank(spender);
        token.transferFrom(address(0), alice, 0);
        assertEq(token.allowance(address(0), spender), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferToTokenContractDoesNotBurnSupply() public {
        assertTrue(token.transfer(address(token), SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function _roundTrip(uint256 amount) private {
        uint256 aliceBefore = token.balanceOf(alice);
        uint256 bobBefore = token.balanceOf(bob);
        vm.prank(alice);
        assertTrue(token.transfer(bob, amount));
        assertEq(token.balanceOf(alice), aliceBefore - amount);
        assertEq(token.balanceOf(bob), bobBefore + amount);
        vm.prank(bob);
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(alice), aliceBefore);
        assertEq(token.balanceOf(bob), bobBefore);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
