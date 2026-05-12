# DAO Layer 1 (Production Web3 Stack)

This folder now contains a contract-first Layer 1 implementation for Identity and Sybil-Resistance, aligned to:

- `layer 1 vertical decoposition.md`
- `layer 1 horizontal decomposition.md`
- `dao layer 1 integration-gates.md`

## Smart Contract Modules

- `contracts/Layer1IdentityRegistry.sol` (`ID-ATTEST + SYBIL-GUARD` boundaries)
- `contracts/Layer1VoiceCreditLedger.sol` (`ZK-MINT credit binding + quadratic deductions`)
- `contracts/Layer1Bridge.sol` (`L1-L2-BRIDGE`, event allowlist, rate limits, readonly queries)
- `contracts/Layer1GateController.sol` (strict gate sequencing `G1 -> G2 -> G3 -> G4 -> G6`, interrupt `G5`)
- `contracts/interfaces/IZKVerifier.sol` (pluggable proof verifier)

## Security/Integrity Rules Encoded

- DID uniqueness and split-attack nullifier prevention
- Minimum proof source count and reputation threshold
- Trusted issuer allowlist
- One-time credit mint per epoch
- Quadratic cost `sum(v_i^2)` enforced in ledger
- Revocation cascade: flag/revoke/freeze + bridge invalidation event
- Bridge event type restrictions and per-block mint throughput limits

## Foundry Setup

1. Install Foundry:
   - [https://book.getfoundry.sh/getting-started/installation](https://book.getfoundry.sh/getting-started/installation)
2. Install test dependency:
   - `forge install foundry-rs/forge-std`
3. Build:
   - `forge build`
4. Test:
   - `forge test -vv`

## CI-Ready Command Set

- **Local full check (PowerShell)**: `./script/ci-test.ps1`
- **Local full check (bash)**: `bash ./script/ci-test.sh`
- **Manual command set**:
  - `forge fmt --check`
  - `forge build`
  - `forge test -vv`
  - `forge snapshot`

## Notes for Mainnet Readiness

- Replace `MockZKVerifier` with audited verifier contracts (Groth16/Plonk).
- Add multisig/timelock controls for privileged owner actions.
- Add invariant/fuzz suites for uniqueness and revocation guarantees.
- Add deployment scripts per target chain and CI checks for static analysis.
