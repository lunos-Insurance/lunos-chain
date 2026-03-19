# Lunos Chain — Compliance Infrastructure

Institutional-grade compliance layer for a regulated zk-validium blockchain built on Polygon CDK / zkSync-style stack.

## System Architecture

Lunos implements **token-scoped compliance enforcement** entirely at the smart contract layer. No modifications to the EVM execution engine, zk circuits, sequencer, or prover are required.

```
┌─────────────────────────────────────────────────────────────────┐
│                     Governance Multisig                         │
│                   (GovernanceExecutor)                          │
└──────┬──────────────┬──────────────────┬───────────────────────┘
       │              │                  │
       ▼              ▼                  ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────────┐
│ Jurisdiction │ │  Approved    │ │   Compliance     │
│  Registry    │ │  Attestors   │ │   Registry       │
│              │ │              │ │                   │
│ jurisdiction │ │ attestor     │ │ wallet→juris→cred │
│ IDs (1=EU…)  │ │ whitelist    │ │ + pending updates │
└──────────────┘ └──────────────┘ └────────┬──────────┘
                                           │
                                           ▼
                                  ┌─────────────────┐
                                  │  Compliance     │
                                  │  Manager        │
                                  │                 │
                                  │ validateTransfer│
                                  │ (view only)     │
                                  └────────┬────────┘
                                           │
                  ┌────────────────────────┤
                  │                        │
                  ▼                        ▼
       ┌──────────────────┐    ┌──────────────────┐
       │ RestrictedToken   │    │ TokenTransfer    │
       │                   │◄──│ Matrix           │
       │ ERC20 + compliance│    │                  │
       │ _update() hook    │    │ from→to→allowed  │
       └──────────────────┘    └──────────────────┘
                  ▲
                  │
       ┌──────────────────┐
       │ RestrictedToken   │
       │ Factory           │
       │                   │
       │ deploys proxies   │
       └──────────────────┘
```

### Core Contracts

| Contract | Path | Responsibility |
|---|---|---|
| **JurisdictionRegistry** | `contracts/core/` | Canonical jurisdiction IDs (immutable once created) |
| **ApprovedAttestors** | `contracts/core/` | Whitelisted KYC provider addresses |
| **ComplianceRegistry** | `contracts/core/` | Wallet credentials with timelocked updates |
| **ComplianceManager** | `contracts/core/` | View-only transfer validation engine |

### Token Contracts

| Contract | Path | Responsibility |
|---|---|---|
| **RestrictedToken** | `contracts/token/` | ERC20 with compliance in `_update()` |
| **TokenTransferMatrix** | `contracts/token/` | Jurisdiction-to-jurisdiction compatibility |
| **RestrictedTokenFactory** | `contracts/token/` | Deploys new token + matrix proxy pairs |

### Governance

| Contract | Path | Responsibility |
|---|---|---|
| **GovernanceExecutor** | `contracts/governance/` | Multisig execution wrapper for system calls |

### Future Modules (Placeholder)

| Contract | Path | Responsibility |
|---|---|---|
| **DIDRegistry** | `contracts/did/` | Optional decentralized identity anchor |
| **FeeManager** | `contracts/fees/` | Future fee routing (issuer, attestation, protocol) |

## Compliance Flow

### Credential Issuance
1. Governance adds jurisdiction IDs via `JurisdictionRegistry.addJurisdiction()`
2. Governance approves attestors via `ApprovedAttestors.addAttestor()`
3. Attestor submits credential via `ComplianceRegistry.submitCredential()`
4. Credential enters pending state: `effectiveBlock = block.number + globalCredentialDelay`
5. After delay, `resolveCredential()` activates the credential

### Token Transfer Validation
When `RestrictedToken.transfer()` is called:

1. `_update()` is invoked (OpenZeppelin ERC20 hook)
2. `_enforceCompliance(from, to)` executes **before** balance mutation
3. Pending credentials are resolved lazily via `ComplianceRegistry.resolveCredential()`
4. Wallet jurisdictions are looked up from `walletJurisdiction` mapping
5. Token checks both jurisdictions are in `acceptedJurisdictions`
6. `ComplianceManager.validateTransfer()` checks:
   - Credentials active
   - Credentials not expired (`block.timestamp < expiry`)
   - Credential levels ≥ `requiredLevel`
   - Jurisdictions registered
7. `TokenTransferMatrix.matrixAllows()` checks jurisdiction compatibility
8. If any check fails → `ComplianceCheckFailed` event + revert
9. If all pass → `super._update()` executes the balance mutation

### Compliance Levels
Hierarchical levels stored as `uint8`:
- **1** = Retail
- **2** = Accredited
- **3** = Institutional

Higher levels satisfy lower requirements (e.g., Institutional satisfies Accredited).

### Timelock Model

| Domain | Controller | Applies To |
|---|---|---|
| **Global Delay** | Governance | Credential issuance, updates, revocations |
| **Token Delay** | Issuer | Matrix updates, token-specific rules |

Resolution: `effectiveBlock = block.number + delay`

Pending updates activate lazily during reads.

## Contract Interactions

```
User Transfer → RestrictedToken._update()
                    │
                    ├── ComplianceRegistry.resolveCredential(sender)
                    ├── ComplianceRegistry.resolveCredential(receiver)
                    ├── Check acceptedJurisdictions
                    ├── ComplianceManager.validateTransfer()
                    │       ├── ComplianceRegistry.getCredential(sender)
                    │       ├── ComplianceRegistry.getCredential(receiver)
                    │       ├── Check active, expiry, level
                    │       └── JurisdictionRegistry.jurisdictionExists()
                    ├── TokenTransferMatrix.matrixAllows()
                    └── super._update() [balance mutation]
```

## Security Invariants

1. **Compliance before mutation** — All checks execute before `super._update()`
2. **Irreversible compliance** — `complianceEnabled` cannot be set to false
3. **Timelock enforcement** — All credential/matrix changes respect delays
4. **Attestor exclusivity** — Only approved attestors issue credentials
5. **Expiry enforcement** — Expired credentials always fail validation
6. **O(1) lookups** — No loops, all checks via mapping lookups
7. **zk-compatible** — No oracles, no async, deterministic execution only

## Project Structure

```
contracts/
├── core/
│   ├── ComplianceManager.sol
│   ├── ComplianceRegistry.sol
│   ├── JurisdictionRegistry.sol
│   └── ApprovedAttestors.sol
├── token/
│   ├── RestrictedToken.sol
│   ├── TokenTransferMatrix.sol
│   └── RestrictedTokenFactory.sol
├── governance/
│   └── GovernanceExecutor.sol
├── did/
│   └── DIDRegistry.sol
├── fees/
│   └── FeeManager.sol
└── interfaces/
    ├── IComplianceManager.sol
    ├── IComplianceRegistry.sol
    ├── IJurisdictionRegistry.sol
    ├── IRestrictedToken.sol
    └── IAttestor.sol

test/
├── compliance/
│   ├── ComplianceRegistry.t.sol
│   └── ComplianceManager.t.sol
└── tokens/
    ├── RestrictedToken.t.sol
    └── TokenTransferMatrix.t.sol

script/
├── DeployCore.s.sol
└── DeployToken.s.sol

audit/
├── checklist.md
├── invariants.md
└── known-risks.md
```

## Getting Started

### Prerequisites
- [Foundry](https://book.getfoundry.sh/getting-started/installation)

### Install Dependencies
```bash
forge install OpenZeppelin/openzeppelin-contracts-upgradeable
forge install foundry-rs/forge-std
```

### Build
```bash
forge build
```

### Test
```bash
forge test
```

### Deploy
```bash
# Deploy core infrastructure
forge script script/DeployCore.s.sol --rpc-url <RPC_URL> --broadcast

# Deploy token infrastructure
forge script script/DeployToken.s.sol --rpc-url <RPC_URL> --broadcast
```

## Enterprise Node Events

Enterprise nodes should index these events for compliance monitoring:

| Event | Contract | Purpose |
|---|---|---|
| `CredentialScheduled` | ComplianceRegistry | New/updated credential pending |
| `CredentialActivated` | ComplianceRegistry | Credential became active |
| `CredentialRevoked` | ComplianceRegistry | Credential revocation scheduled |
| `MatrixUpdateScheduled` | TokenTransferMatrix | Matrix change pending |
| `MatrixUpdateActivated` | TokenTransferMatrix | Matrix change activated |
| `RestrictedTokenTransfer` | RestrictedToken | Compliant transfer completed |
| `ComplianceCheckFailed` | RestrictedToken | Transfer rejected |

## License

MIT
