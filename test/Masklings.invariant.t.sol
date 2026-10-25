// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Masklings} from "../src/Masklings.sol";

/// @dev Tracks an independent ledger through successful and rejected actions.
contract MasklingsHandler is Test {
    Masklings private immutable token;
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(Masklings token_) {
        token = token_;
        for (uint256 i; i < actors.length; ++i) {
            actors[i] = makeAddr(string.concat("holder ", vm.toString(i)));
        }
        expectedBalance[actors[0]] = SUPPLY;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed, bool overspend) public {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[from];
        uint256 amount = overspend ? bound(amountSeed, balance + 1, type(uint256).max) : _amount(amountSeed, balance);
        vm.prank(from);
        (bool success, bytes memory result) = address(token).call(abi.encodeCall(IERC20.transfer, (to, amount)));
        assertEq(success, !overspend, "transfer authorization");
        if (success) {
            assertTrue(abi.decode(result, (bool)));
            expectedBalance[from] -= amount;
            expectedBalance[to] += amount;
        } else {
            assertEq(
                result, abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount)
            );
        }
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, uint8 mode) public {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 amount;
        if (mode % 5 == 1) amount = type(uint256).max;
        else if (mode % 5 == 2) amount = type(uint256).max - 1;
        else if (mode % 5 == 3) amount = amountSeed;
        else if (mode % 5 == 4) amount = bound(amountSeed, 0, SUPPLY);
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 amountSeed, bool overspend)
        public
    {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 balance = expectedBalance[from];
        uint256 approved = expectedAllowance[from][spender];
        uint256 limit = balance < approved ? balance : approved;
        uint256 amount = overspend ? bound(amountSeed, limit + 1, type(uint256).max) : _amount(amountSeed, limit);
        vm.prank(spender);
        (bool success, bytes memory result) =
            address(token).call(abi.encodeCall(IERC20.transferFrom, (from, to, amount)));
        assertEq(success, !overspend, "transferFrom authorization");
        if (success) {
            assertTrue(abi.decode(result, (bool)));
            expectedBalance[from] -= amount;
            expectedBalance[to] += amount;
            if (approved != type(uint256).max) expectedAllowance[from][spender] -= amount;
        } else if (amount > approved) {
            assertEq(
                result,
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount)
            );
        } else {
            assertEq(
                result, abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount)
            );
        }
    }

    /// @dev Failed calls leave the ghost ledger untouched; the invariant checks all balances
    /// and allowances afterwards, including allowances spent before an invalid recipient is noticed.
    function rejectZeroAddress(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, uint8 operation) public {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        bytes memory data;
        bytes memory expectedError;
        address caller = owner;
        if (operation % 4 == 0) {
            data = abi.encodeCall(IERC20.transfer, (address(0), _amount(amountSeed, expectedBalance[owner])));
            expectedError = abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0));
        } else if (operation % 4 == 1) {
            data = abi.encodeCall(IERC20.approve, (address(0), amountSeed));
            expectedError = abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0));
        } else if (operation % 4 == 2) {
            uint256 approved = expectedAllowance[owner][spender];
            uint256 balance = expectedBalance[owner];
            uint256 limit = balance < approved ? balance : approved;
            data = abi.encodeCall(IERC20.transferFrom, (owner, address(0), _amount(amountSeed, limit)));
            caller = spender;
            expectedError = abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0));
        } else {
            // Only rejection is required here: allowance validation may reject before sender validation.
            data = abi.encodeCall(IERC20.transferFrom, (address(0), owner, 0));
            caller = spender;
        }
        vm.prank(caller);
        (bool success, bytes memory result) = address(token).call(data);
        assertFalse(success, "zero address accepted");
        if (expectedError.length != 0) assertEq(result, expectedError);
    }

    function revokeAndTrySpend(uint256 ownerSeed, uint256 spenderSeed, uint256 recipientSeed) public {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address recipient = actors[recipientSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, 0));
        expectedAllowance[owner][spender] = 0;
        vm.prank(spender);
        (bool success, bytes memory result) =
            address(token).call(abi.encodeCall(IERC20.transferFrom, (owner, recipient, 1)));
        assertFalse(success, "revoked spender moved tokens");
        assertEq(result, abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
    }

    /// @dev Select a funded actor so this property always moves value, even after full-balance transfers.
    function roundTrip(uint256 ownerSeed, uint256 recipientSeed, uint256 amountSeed) public {
        uint256 ownerIndex = ownerSeed % actors.length;
        for (uint256 i; i < actors.length && expectedBalance[actors[ownerIndex]] == 0; ++i) {
            ownerIndex = (ownerIndex + 1) % actors.length;
        }
        address owner = actors[ownerIndex];
        address recipient = actors[(ownerIndex + 1 + recipientSeed % (actors.length - 1)) % actors.length];
        uint256 ownerBefore = expectedBalance[owner];
        uint256 recipientBefore = expectedBalance[recipient];
        uint256 amount = _amount(amountSeed, ownerBefore);
        if (amount == 0) amount = 1;

        vm.prank(owner);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(owner), ownerBefore - amount);
        assertEq(token.balanceOf(recipient), recipientBefore + amount);
        assertEq(token.totalSupply(), SUPPLY);
        vm.prank(recipient);
        assertTrue(token.transfer(owner, amount));
        assertEq(token.balanceOf(owner), ownerBefore);
        assertEq(token.balanceOf(recipient), recipientBefore);
        // No ghost update: the round trip must restore the entire ledger.
    }

    function _amount(uint256 seed, uint256 limit) private pure returns (uint256) {
        if (seed % 4 == 0) return 0;
        if (seed % 4 == 1) return limit == 0 ? 0 : 1;
        if (seed % 4 == 2) return limit;
        return bound(seed, 0, limit);
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract MasklingsInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    Masklings private token;
    MasklingsHandler private handler;

    function setUp() public {
        token = new Masklings();
        handler = new MasklingsHandler(token);
        assertTrue(token.transfer(handler.actors(0), SUPPLY));

        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.transferFrom.selector;
        selectors[3] = handler.rejectZeroAddress.selector;
        selectors[4] = handler.revokeAndTrySpend.selector;
        selectors[5] = handler.roundTrip.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_supplyBalancesAndAllowancesMatchModel() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.name(), "Masklings");
        assertEq(token.symbol(), "MASKLINGS");
        assertEq(token.decimals(), 18);
        uint256 accounted;
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            uint256 balance = token.balanceOf(actor);
            assertEq(balance, handler.expectedBalance(actor));
            accounted += balance;
            assertEq(token.allowance(actor, address(0)), 0);
            assertEq(token.allowance(address(0), actor), 0);
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(actor, spender), handler.expectedAllowance(actor, spender));
            }
        }
        assertEq(accounted, SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(this)), 0);
    }

    /// @dev Pin meaningful branches independently of random selector/argument selection.
    function test_handlerExercisesSpendingRollbackRevocationAndRoundTrips() public {
        handler.approve(0, 1, SUPPLY, 4);
        handler.transferFrom(0, 2, 1, 1, false);
        invariant_supplyBalancesAndAllowancesMatchModel();
        handler.rejectZeroAddress(0, 1, 2, 2);
        invariant_supplyBalancesAndAllowancesMatchModel();
        handler.transferFrom(0, 2, 1, type(uint256).max, true);
        invariant_supplyBalancesAndAllowancesMatchModel();
        handler.approve(0, 1, 0, 1);
        handler.transferFrom(0, 2, 1, 1, false);
        invariant_supplyBalancesAndAllowancesMatchModel();
        handler.revokeAndTrySpend(0, 1, 2);
        invariant_supplyBalancesAndAllowancesMatchModel();
        handler.roundTrip(0, 1, 2);
        invariant_supplyBalancesAndAllowancesMatchModel();
        handler.transfer(0, 3, 2, false);
        handler.transfer(0, 3, type(uint256).max, true);
        invariant_supplyBalancesAndAllowancesMatchModel();
    }
}
