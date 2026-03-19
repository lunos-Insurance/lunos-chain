# Known Risks — Lunos Compliance Layer

## R-1: Lazy Credential Resolution
**Severity:** Medium
**Description:** Credentials are resolved lazily during transfer validation. If `resolveCredential()` is not called, a pending credential may not be active when expected.
**Mitigation:** `RestrictedToken._enforceCompliance()` calls `resolveCredential()` before validation. Off-chain infrastructure should also periodically resolve pending updates.

## R-2: Block Number Dependency for Timelocks
**Severity:** Low
**Description:** Timelocks use `block.number` which in zk-validium/rollup contexts may have different semantics than L1.
**Mitigation:** `block.number` is deterministic and safe in Polygon CDK/zkSync-style chains per spec. Monitor sequencer behavior.

## R-3: Attestor Compromise
**Severity:** High
**Description:** A compromised attestor can issue fraudulent credentials. Credentials would become active after the global delay.
**Mitigation:** Global timelock provides a window for governance to revoke the attestor. Off-chain monitoring should detect anomalous credential submissions.

## R-4: Governance Key Compromise
**Severity:** Critical
**Description:** Compromise of the governance multisig could lead to malicious upgrades, attestor changes, or jurisdiction modifications.
**Mitigation:** Use high-threshold multisig (e.g., 3/5 or 4/7). Consider adding timelock to governance actions in future. Off-chain monitoring for governance transactions.

## R-5: Matrix Update Race Condition
**Severity:** Low
**Description:** A transfer executed in the same block as a matrix resolution could see stale matrix state.
**Mitigation:** Token delay ensures sufficient notification period. Enterprise nodes should index `MatrixUpdateScheduled` events.

## R-6: Credential Expiry Granularity
**Severity:** Low
**Description:** Credential expiry uses `block.timestamp`. In zk-validium chains, timestamp granularity depends on sequencer batch timing.
**Mitigation:** Set expiry dates with sufficient margin. Do not rely on second-level precision.

## R-7: Factory Proxy Deployment
**Severity:** Low
**Description:** RestrictedTokenFactory deploys minimal ERC1967 proxies. If the implementation address is compromised or upgraded maliciously, all tokens using that implementation are affected.
**Mitigation:** Implementation upgrades require governance approval. Each token proxy is independently upgradeable by its issuer.

## R-8: Missing Credential Default
**Severity:** Info
**Description:** Wallets without credentials have default zero values (level=0, expiry=0, active=false). This correctly fails validation but relies on the default Solidity behavior.
**Mitigation:** Explicitly checked in `ComplianceManager.validateTransfer()`.
