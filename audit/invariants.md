# Security Invariants — Lunos Compliance Layer

## Critical Invariants

### INV-1: Compliance Pre-State Check
Compliance checks MUST execute before any token balance mutation.
- Location: `RestrictedToken._update()`
- Enforcement: `_enforceCompliance()` is called before `super._update()`

### INV-2: Global Timelock on Credentials
Credential updates MUST respect `globalCredentialDelay`.
- Formula: `effectiveBlock = block.number + globalCredentialDelay`
- Location: `ComplianceRegistry.submitCredential()`, `scheduleCredentialUpdate()`, `scheduleCredentialRevocation()`

### INV-3: Token Timelock on Matrix
Matrix updates MUST respect `tokenDelay`.
- Formula: `effectiveBlock = block.number + tokenDelay`
- Location: `TokenTransferMatrix.scheduleMatrixUpdate()`

### INV-4: Compliance Irreversibility
Once `complianceEnabled = true`, it CANNOT be set to `false`.
- Location: `RestrictedToken`
- Enforcement: No setter exists. `_authorizeUpgrade` checks compliance is still enabled.

### INV-5: Attestor Exclusivity
Only addresses in `ApprovedAttestors` may issue credentials.
- Location: `ComplianceRegistry` — `onlyAttestor` modifier

### INV-6: Expiry Enforcement
Expired credentials MUST invalidate transfers.
- Check: `block.timestamp < credential.expiry`
- Location: `ComplianceManager.validateTransfer()`

### INV-7: Constant-Time Matrix Lookup
Matrix lookups MUST be O(1).
- Implementation: `mapping(uint256 => mapping(uint256 => bool))`
- No iteration over jurisdictions permitted.

### INV-8: No Loops Over Credentials
Transfer validation MUST NOT iterate over wallet credentials.
- Wallets declare their jurisdiction via `setWalletJurisdiction()`
- Single-credential lookup per wallet per transfer

## Storage Layout Invariants

### INV-S1: Storage Gap Preservation
All contracts MUST maintain `__gap` arrays.
Future upgrades MUST NOT reorder existing storage slots.

### INV-S2: No Constructor State
All contracts use `_disableInitializers()` in constructors.
State is set exclusively through `initialize()` functions.

## Access Control Invariants

### INV-A1: Governance Scope
Governance controls: JurisdictionRegistry, ApprovedAttestors, globalCredentialDelay, upgrades.

### INV-A2: Attestor Scope
Attestors control: credential submission, credential updates, credential revocation (own credentials).

### INV-A3: Issuer Scope
Issuers control: mint, burn, matrix updates, required level, accepted jurisdictions.

### INV-A4: User Scope
Users have NO privileged permissions. They may only set their own wallet jurisdiction.
