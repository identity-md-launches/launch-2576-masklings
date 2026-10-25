// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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
        uint256 amount = overspend ? balance + 1 : bound(amountSeed, 0, balance);
        vm.prank(from);
        (bool success, bytes memory result) = address(token).call(abi.encodeCall(IERC20.transfer, (to, amount)));
        assertEq(success, !overspend, "transfer authorization");
        if (success) {
            assertTrue(abi.decode(result, (bool)));
            expectedBalance[from] -= amount;
            expectedBalance[to] += amount;
        }
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, uint8 mode) public {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 amount = mode % 3 == 0 ? 0 : mode % 3 == 1 ? type(uint256).max : bound(amountSeed, 0, SUPPLY);
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
        uint256 amount = overspend ? limit + 1 : bound(amountSeed, 0, limit);
        vm.prank(spender);
        (bool success, bytes memory result) =
            address(token).call(abi.encodeCall(IERC20.transferFrom, (from, to, amount)));
        assertEq(success, !overspend, "transferFrom authorization");
        if (success) {
            assertTrue(abi.decode(result, (bool)));
            expectedBalance[from] -= amount;
            expectedBalance[to] += amount;
            if (approved != type(uint256).max) expectedAllowance[from][spender] -= amount;
        }
    }
}

contract MasklingsInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    Masklings private token;
    MasklingsHandler private handler;

    function setUp() public {
        token = new Masklings();
        handler = new MasklingsHandler(token);
        assertTrue(token.transfer(handler.actors(0), SUPPLY));

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.transferFrom.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_supplyBalancesAndAllowancesMatchModel() public view {
        assertEq(token.totalSupply(), SUPPLY);
        uint256 accounted;
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            uint256 balance = token.balanceOf(actor);
            assertEq(balance, handler.expectedBalance(actor));
            accounted += balance;
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
}
