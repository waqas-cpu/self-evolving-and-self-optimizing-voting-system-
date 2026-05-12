# Layer 2 Production Build

Production Solidity implementation of Layer 2 (State & Execution) based on the Layer 2 vertical, horizontal, and integration-gate specifications.

## Implemented Gate/Agent Contracts

- `contracts/Layer2AuditTrail.sol` (cross-gate audit sink and event schema)
- `contracts/IdentityBinding.sol` (Gate 1 / Agent 5)
- `contracts/VoiceCreditLedger.sol` (Gate 2 / Agent 1)
- `contracts/libraries/QuadraticMath.sol` (Gate 2 / Agent 2 pure math)
- `contracts/ProposalLifecycle.sol` (Gate 3 / Agent 3 + emergency controls)
- `contracts/ParameterRegistry.sol` (Gate 4 / Agent 6 timelock + bounds + veto)
- `contracts/AnalyticsGate.sol` (Gate 5 oracle analytics, read-only to core logic)
- `contracts/ExecutionRouter.sol` (Agent 4 deterministic execution routing)

## Security Properties Encoded

- Deterministic quadratic cost (`sum(v_i^2)`), no oracle dependency in voting core.
- Gate-by-gate structured audit records (`gateId`, `actionId`, `subjectId`, `success`, `severity`, `contextHash`).
- 1 DID -> 1 voting account mapping with revocation and compromised status.
- Credit lock/release flow tied to proposal lifecycle.
- Proposal state machine and deterministic tie-break rule support.
- Hard bounded parameter updates with timelock and veto-safe reset.
- Emergency stop path that reverts parameters to baseline safe mode.

## Test

- `forge test -vv`

## CI Script

- PowerShell: `./script/ci-test.ps1`
- Bash: `bash ./script/ci-test.sh`
