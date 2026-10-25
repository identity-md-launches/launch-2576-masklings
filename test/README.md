# Masklings tests

Run without network access using the already vendored dependencies and Solidity 0.8.26:

```sh
forge build --offline --out test/scratch/out --cache-path test/scratch/cache
FOUNDRY_FUZZ_SEED=0x6b58c24e754a78c3ea57363e683242a9616d6bbce0e544b4cd7877227bb3d38a forge test --offline --out test/scratch/out --cache-path test/scratch/cache
```

Build artifacts go to disposable scratch space. No submitted test imports anything from
scratch or the supplied protected checks. The tests require no RPC, environment reads,
FFI, dependency installation, or configuration changes.

The existing `Masklings.t.sol` covers metadata, constructor minting (including factory
deployment), events, exact transfers, allowance accounting, prohibited administrative
entry points, and basic failures. Its fuzz inputs now avoid discarded addresses.
`Masklings.properties.t.sol` adds repeated-action and boundary properties. Each fuzz
property uses 1,000 runs through inline Foundry configuration.

The five discovery perspectives in the supplied Pashov reference were applied to this
token, using the supplied Trail of Bits reference to review input bounds and properties:

| Perspective | Property and grounding | Coverage |
| --- | --- | --- |
| Conservation | The constructor creates exactly `10**27` units once (`src/Masklings.sol:10-15`); all subsequent movement conserves balances. | Initial mint tests; ghost balances and fixed supply after every handler call; recipient contracts remain part of supply. |
| State transitions | Approvals replace the owner's allowance; finite spends consume it, failures roll back, and revocation removes authority (`ERC20.sol:132-158,284-315`). | Independent allowance ledger; overwrite, retry after funding, exhausted-allowance and revocation tests. |
| Round trips | Ordinary transfers have no tax, conversion, or rounding (`ERC20.sol:171-218`). Sending an amount back restores balances; splitting a transfer has the same final effect. | Repeated round trips with pre-funded recipients; split-versus-single delegated transfers; handler round trips. |
| Adversarial value/liveness | A funded holder can move its full balance; neither transaction origin nor a revoked approval grants spending authority (`ERC20.sol:109-113,154-158`). | Full-balance and one-unit inputs, self-transfers, maximum attempted spends, origin impersonation, and revocation. |
| Token semantics | Zero-value transfers preserve balances and allowances; invalid addresses revert; maximum approval remains infinite while maximum-minus-one is finite. | Event assertions, zero-address failures, zero delegated transfers, and finite/infinite allowance transitions. |

`ERC20.sol` above refers to the vendored
`lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol`. No vault, interest,
conversion, governance, or liquidity-pool accounting is implemented by this token.

The invariant suite extends the existing four-actor handler. It runs 256 sequences of
128 actions, selecting transfers, approvals, delegated transfers, invalid-address calls,
revocation attempts, and round trips. Amount generation explicitly includes zero, one
smallest unit, the available balance/allowance, arbitrary bounded amounts, and excessive
amounts up to `uint256.max`. Approvals include zero, arbitrary values, maximum-minus-one,
and maximum. Actor collisions exercise self-transfers and self-approvals.

Only these six handler selectors are targeted. The ghost ledger is initialized from the
specified supply and updated from requested actions, not by copying observed balances.
Successful calls must return true; expected failures are caught and asserted, leaving
the ledger untouched. Unexpected handler reverts fail the campaign. After each action,
all 4 balances and 16 actor-to-actor allowances are compared with the ledger, balances
must sum to the original supply, and metadata and zero-address state must remain intact.
Round trips deliberately select a funded actor and check intermediate balances as well
as the restored state. A deterministic handler test pins spending, rollback, revocation,
round-trip, and full-balance branches independently of random selection.

The closed actor set makes conservation enumerable. It is not a universal proof over
all addresses or arbitrary bytecode. The original launch-flow test checks token movements
only; actual Uniswap initialization and swaps belong to the supplied protected launch
checks and are not simulated by this standalone token repository.
