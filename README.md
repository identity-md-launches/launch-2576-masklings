# Masklings (MASKLINGS)

`src/Masklings.sol:Masklings` is a fixed supply ERC-20 built on the vendored
OpenZeppelin Contracts v5.0.2 implementation.

| Parameter | Value |
| --- | --- |
| Name | `Masklings` |
| Symbol | `MASKLINGS` |
| Decimals | `18` |
| Whole-token supply | `1,000,000,000` |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`) |
| Constructor payment | None; constructor is nonpayable |
| Initial recipient | Immediate deployer, `msg.sender` |
| Launch chain | Ethereum, chain ID `1` |

The constructor mints the entire supply once, emitting one
`Transfer(address(0), deployer, INITIAL_SUPPLY)` event. `INITIAL_SUPPLY` is a
public constant. When a factory deploys the token, the factory receives the
whole supply; neither the transaction origin nor any other recipient receives
an allocation in the constructor. The constructor makes no external calls.

## Behavior and assumptions

The requested token uses ordinary ERC-20 transfers and approvals. There are no
transfer taxes, transfer limits, rebases, minting entry points, burning entry
points, owner roles, pause controls, blocklists, seizure powers, upgrades,
external dependencies at runtime, or initialization steps. All transfers
deliver the requested amount and preserve total supply. The token needs no
privileged addresses or chain-specific configuration.

- `transfer` and `transferFrom` return `true` on success and emit `Transfer`.
  Failures revert with OpenZeppelin's ERC-6093 custom errors and roll back all
  state, including any allowance deduction.
- Transfers to the zero address revert, including zero-amount transfers.
  Zero-amount transfers between nonzero addresses succeed. Self-transfers
  preserve balances but still require sufficient balance and, for
  `transferFrom`, allowance.
- `approve` sets (replaces) the caller's allowance for a nonzero spender and
  emits `Approval`. Approving zero revokes permission. Approvals do not move
  tokens and can exceed the owner's current balance.
- `transferFrom` requires the holder's allowance to the caller. Finite
  allowances decrease by the amount spent; `type(uint256).max` is an unlimited
  allowance and does not decrease. OpenZeppelin v5 does not emit `Approval`
  when an allowance is spent; integrations should read `allowance` for its
  current value.
- No receiver callback runs when tokens move to a contract. Sending tokens
  to a contract that cannot return them, including the token contract itself,
  can permanently lock them. No administrator can recover them. The token
  accepts no ordinary ETH payment and exposes no asset recovery function.

## Build and checks

Run from the repository root using Foundry and Solidity `0.8.26`:

```sh
forge build
FOUNDRY_FUZZ_SEED=0x6b58c24e754a78c3ea57363e683242a9616d6bbce0e544b4cd7877227bb3d38a forge test
forge fmt --check
sha256sum -c DEPENDENCIES.sha256
```

`foundry.toml` pins the compiler, targets Cancun, enables the optimizer with
200 runs, and sets `bytecode_hash = "none"`. FFI and filesystem permissions
are disabled. Solidity sources and test dependencies are ordinary files under
`lib/`; no submodules, package manager, RPC connection, or dependency download
is needed. The build machine must already provide Foundry and the pinned
compiler. Dependency versions, archive hashes, and licenses are recorded in
`DEPENDENCIES.md` and `DEPENDENCIES.sha256`.

`test/Masklings.t.sol` checks metadata and the exact mint, direct and factory
deployment, events, transfers, approvals, unlimited allowances, revocation,
zero amounts, self-transfers, insufficient balance or allowance, invalid
recipients, rollback, and rejected administrative selectors. It also checks
the exact token movements for distribution, claims, and pool interactions.
That test models token transfers; it does not deploy or simulate a DEX.
Five fuzz tests run 512 cases each. `test/Masklings.invariant.t.sol` checks a
separate balance and allowance model across four holders over 128 random
sequences of 64 calls, including expected failures.

Tests do not read or mutate environment variables, access files, fork chains,
or depend on an externally supplied signer. The shell seed controls Foundry's
fuzzer only. Each test starts from an independent deployment.

## Deployment and launch responsibilities

The sole production contract is `Masklings`; its Solidity identifier is also
the token contract identifier for the separate launch manifest step. Deploy
its compiled creation bytecode directly with no appended constructor
arguments and no ETH. The artifact is `out/Masklings.sol/Masklings.json`.
There are no linked libraries, application contracts, or proxy deployment.
No deployment transaction or manifest is included in this deliverable.

The launch service prepares the manifest, reviews and deploys the artifact,
and verifies the source on the explorer with the pinned build settings.
It must confirm the name, symbol, decimals, supply, constructor mint event,
and the factory's full balance immediately after creation and before
distribution. The factory then performs the launch's allocations: 10% to
the launch distributor, 80% for the pool, and the remaining 10% to the
requester's recipient. The token has no allocation or liquidity logic; pool
configuration and launch economics are the launch service's responsibility.
The supplied protected integration checks exercise its actual pool flow.

The local distribution test uses test actors, not deployment addresses.
The production contract neither needs nor embeds a recipient, router, oracle,
factory address, or deployer key. Its constructor recipient is always the
actual creating address.

## After launch

No configuration setters, owner handoff, maintenance transactions, keepers,
or ongoing administrator are required. The factory is responsible for
distributing its initial balance. Holders control their tokens and approvals;
integrators should request only the allowance needed and account for the
standard ERC-20 approval replacement race. To change an existing allowance,
revoke it and wait for confirmation before granting the replacement; a
spender may still consume the old allowance before the revocation confirms.

Local validation covers compilation, unit tests, fuzzing, stateful invariant
testing, formatting, and vendored-file integrity. The protected launch harness
is not runnable from the supplied excerpts alone: its launch infrastructure,
resolved manifest, and floor tests belong to the independent verifier.
Slither and Mythril were not run locally. Tests and this implementation review
are not an independent security audit; the separate contributor review and
launch checks remain the launch service's responsibility.
