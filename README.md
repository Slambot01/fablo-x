# Fablo-FabricX

A proof-of-concept tool that generates configuration and manages the lifecycle of Hyperledger Fabric-X networks — bringing the Fablo experience to Fabric-X.

Built as part of my application for the [LFDT Mentorship: Fablo + Fabric-X Integration](https://github.com/LF-Decentralized-Trust-Mentorships/mentorship-program/issues/83).

## What This Does

| Capability | Status |
|-----------|--------|
| Generate Fabric-X configs from JSON schema | ✅ Working |
| Dynamic topology (arbitrary endorsers/owners) | ✅ Working |
| Bootstrap a local Fabric-X network | ✅ Working |
| Full network lifecycle (up/down/status) | ✅ Working |
| Automated token lifecycle E2E test | ✅ Working |

## Quick Start

### Prerequisites
- WSL2 with Ubuntu (or native Linux/macOS)
- Docker Desktop with WSL integration enabled
- Go 1.24+ installed
- Node.js 18+ installed
- Fabric-X samples set up at ~/lfdt-project/fabric-x/samples/tokens/
  (follow [Fabric-X setup instructions](https://github.com/hyperledger/fabric-x))

### Generate Configuration
```bash
npm install
npm run generate         # generates all Fabric-X config files
npm run verify           # validates generated output matches reference
npm run generate:verify  # both in one step
```

### Network Lifecycle
```bash
./fablo-fabricx.sh up      # start the full Fabric-X network
./fablo-fabricx.sh status  # check container health
./fablo-fabricx.sh test    # run automated token lifecycle E2E test
./fablo-fabricx.sh down    # tear down everything
```

### What Happens During `./fablo-fabricx.sh up`
- Creates Docker network (`fabric_test`)
- Starts `committer-test-node` (orderer + committer + DB)
- Creates `token_namespace` on the ledger
- Starts all FSC nodes (issuer, endorser1, endorser2, owner1, owner2)
- Waits for all health checks to pass
- Initializes the endorser
- Prints endpoint URLs

### What Happens During `./fablo-fabricx.sh test`
- Verifies all 5 FSC nodes are healthy
- Issues 100 EURX tokens to alice (owner1)
- Issues 50 EURX tokens to carlos (owner2)
- Verifies balances
- Transfers 30 EURX from alice to carlos
- Verifies final balances (alice: 70, carlos: 80)
- Checks transaction histories
- Reports PASS/FAIL

## Architecture

This POC explores what a Fablo integration for Fabric-X would look like. It maps Fablo's generation pipeline to support Fabric-X's decomposed FSC (Fabric Smart Client) architecture. Instead of monolithic peers, this tool generates logic for lightweight nodes that interact over a P2P websocket mesh while utilizing external committer infrastructures. For a detailed breakdown of the components and mappings, please refer to [docs/architecture-mapping.md](docs/architecture-mapping.md).

### Fabric-X Components
| Component | Image | Role |
|-----------|-------|------|
| committer-test-node | `ghcr.io/hyperledger/fabric-x-committer-test-node:0.1.7` | Orderer + Committer + DB |
| issuer | Built from source (`PLATFORM=fabricx`) | Issues tokens |
| endorser1 | Built from source (`PLATFORM=fabricx`) | Endorses transactions |
| endorser2 | Built from source (`PLATFORM=fabricx`) | Endorses transactions (delivery) |
| owner1 | Built from source (`PLATFORM=fabricx`) | Holds/transfers tokens |
| owner2 | Built from source (`PLATFORM=fabricx`) | Holds/transfers tokens |

### API Endpoints
| Endpoint | Method | Description |
|----------|--------|-------------|
| `/healthz` | GET | Health check |
| `/readyz` | GET | Readiness check |
| `/endorser/init` | POST | Initialize token parameters |
| `/issuer/issue` | POST | Issue tokens |
| `/owner/accounts` | GET | List accounts |
| `/owner/accounts/{id}` | GET | Account balance |
| `/owner/accounts/{id}/transfer` | POST | Transfer tokens |
| `/owner/accounts/{id}/transactions` | GET | Transaction history |

## Key Discoveries During Development

During deployment, I discovered and fixed two undocumented issues:

- **Channel Name Mismatch**: The xdev setup path creates channel `mychannel`, but all FSC node configs referenced `arma` (the ansible path name). Fixed by updating all 5 core.yaml files.
- **Namespace Creation Flags**: The `fxconfig namespace create` command requires specific flags including `--mspConfigPath` pointing to `channel_admin` (not Admin) and a `--pk` flag that is deprecated but still required.

These are documented in detail in `docs/evidence/ANALYSIS.md`.

## Project Structure
```text
├── fablo-fabricx.sh          # Network lifecycle manager
├── src/
│   ├── generate.ts           # Dynamic config generator
│   └── verify.ts             # Output verification
├── schema/
│   ├── fablo-config-fabricx.json    # Network topology definition
│   └── FabloConfigJson.fabricx.ts   # TypeScript type definitions
├── templates/
│   ├── docker-compose-fabricx.ejs   # Docker compose template
│   ├── fsc-core-yaml.ejs           # FSC node config template
│   └── routing-config.ejs          # Routing config template
├── generated/                 # Reference output files
├── docs/
│   ├── architecture-mapping.md
│   ├── fablo-codebase-changes.md
│   └── evidence/
│       ├── ANALYSIS.md
│       ├── fabric-x-evidence.txt
│       ├── fabric-x-token-lifecycle.txt
│       └── collect_evidence.sh
└── e2e/                       # (test artifacts)
```

## Related Work

- **BFT Validation PR**: [PR #685 on upstream Fablo](https://github.com/hyperledger-labs/fablo/pull/685) — adds BFT consensus validation
- **Mentorship Issue**: [#83](https://github.com/LF-Decentralized-Trust-Mentorships/mentorship-program/issues/83)
- **Fablo Issue**: [#611](https://github.com/hyperledger-labs/fablo/issues/611) — Fabric-X support tracking

## Author

**Ritesh Pandit**
- GitHub: [@Slambot01](https://github.com/Slambot01)
- Email: riteshpandit1708@gmail.com
