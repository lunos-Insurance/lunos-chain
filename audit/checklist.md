# Audit Checklist — Lunos Compliance Layer

## Access Control
- [ ] Only governance can add jurisdictions
- [ ] Only governance can add/remove attestors
- [ ] Only governance can update global credential delay
- [ ] Only approved attestors can submit credentials
- [ ] Only attestor or governance can revoke credentials
- [ ] Only token issuer can mint/burn
- [ ] Only token issuer can update matrix
- [ ] Only token issuer can set required level
- [ ] Only token issuer can set accepted jurisdictions

## Timelock Enforcement
- [ ] Credential issuance respects global delay
- [ ] Credential updates respect global delay
- [ ] Credential revocations respect global delay
- [ ] Matrix updates respect token delay
- [ ] Pending updates activate only after effective block

## Compliance Enforcement
- [ ] `_beforeTokenTransfer` enforces compliance on every transfer
- [ ] Compliance cannot be disabled once enabled
- [ ] Expired credentials fail transfer validation
- [ ] Missing credentials fail transfer validation
- [ ] Insufficient level fails transfer validation
- [ ] Invalid jurisdiction fails transfer validation
- [ ] Matrix incompatibility fails transfer validation
- [ ] Mints and burns bypass compliance (issuer-controlled)

## Upgrade Safety
- [ ] All contracts use UUPS proxy pattern
- [ ] All contracts use `_disableInitializers()` in constructor
- [ ] All contracts have storage gaps (`__gap`)
- [ ] Storage layout order is documented and frozen
- [ ] `_authorizeUpgrade` is owner-only

## Event Coverage
- [ ] `CredentialScheduled` emitted on submission
- [ ] `CredentialActivated` emitted on resolution
- [ ] `CredentialRevoked` emitted on revocation
- [ ] `MatrixUpdateScheduled` emitted on matrix change
- [ ] `MatrixUpdateActivated` emitted on matrix resolution
- [ ] `RestrictedTokenDeployed` emitted on factory deploy
- [ ] `ComplianceCheckFailed` emitted on transfer failure
- [ ] `JurisdictionAdded` emitted on jurisdiction creation
- [ ] `AttestorAdded` / `AttestorRemoved` emitted
- [ ] `GovernanceActionExecuted` emitted on governance call

## zk-validium Compatibility
- [ ] No external oracle dependencies
- [ ] No asynchronous verification
- [ ] All lookups are O(1)
- [ ] No unbounded loops
- [ ] Deterministic execution guaranteed
- [ ] `block.number` used for timelock (safe in zk context)
