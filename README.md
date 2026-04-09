# Fablo-FabricX

A proof-of-concept tool that generates configuration and manages the lifecycle of Hyperledger Fabric-X networks — bringing the Fablo experience to Fabric-X.

Built as part of my application for the [LFDT Mentorship: Fablo + Fabric-X Integration](https://github.com/LF-Decentralized-Trust-Mentorships/mentorship-program/issues/83).

## What This Does

| Capability | Status |
|-----------|--------|
| Generate Fabric-X configs from JSON schema | ✅ Working |
| Dynamic topology (arbitrary endorsers/owners) | ✅ Working |
| **Connected pipeline: generate → deploy → start** | ✅ Working |
| Full network lifecycle (up/down/status) | ✅ Working |
| Automated token lifecycle E2E test | ✅ Working |

## The Fablo-FabricX Pipeline

```text
┌─────────────────────┐    ┌──────────────────────┐    ┌─────────────────┐
│  fablo-config-      │    │   Config Generator   │    │    Fabric-X     │
│  fabricx.json       │───▶│   (EJS templates)    │───▶│    Network      │
│                     │    │                      │    │    (Docker)     │
│  Define topology:   │    │  Produces:           │    │                 │
│  - endorsers        │    │  - core.yaml / node  │    │  Running with   │
│  - owners           │    │  - routing-config    │    │  YOUR generated │
│  - issuer           │    │  - docker-compose    │    │  configs        │
└─────────────────────┘    └──────────────────────┘    └─────────────────┘
```

The `./fablo-fabricx.sh up` command executes this entire pipeline:
1. **Generates** all config files from your JSON topology definition
2. **Deploys** generated configs into the Fabric-X deployment (backing up originals)
3. **Starts** the committer infrastructure + all FSC nodes
4. **Verifies** health of all nodes
5. The `down` command **restores** original configs automatically

## Quick Start

### Prerequisites
- WSL2 with Ubuntu (or native Linux/macOS)
- Docker Desktop with WSL integration enabled
- Go 1.24+ installed
- Node.js 18+ installed
- Fabric-X samples set up at ~/lfdt-project/fabric-x/samples/tokens/
  (follow [Fabric-X setup instructions](https://github.com/hyperledger/fabric-x))

### One Command Start
```bash
npm install

# Generate + Deploy + Start — all in one command
./fablo-fabricx.sh up

# Verify the network works
./fablo-fabricx.sh test

# Check status
./fablo-fabricx.sh status

# Tear down (restores original configs)
./fablo-fabricx.sh down
```

### Step by Step
```bash
# 1. Generate configs from your topology definition
./fablo-fabricx.sh generate

# 2. Start the network with generated configs
./fablo-fabricx.sh up

# 3. Run automated E2E token lifecycle test
./fablo-fabricx.sh test

# 4. Tear down
./fablo-fabricx.sh down
```

### Change the Topology

Edit `schema/fablo-config-fabricx.json` to add/remove endorsers, owners, etc.
Then run `./fablo-fabricx.sh up` — the generator automatically produces new configs
and deploys them to the network.

### Generate & Verify Only
```bash
npm run generate         # generates all Fabric-X config files
npm run verify           # validates generated output matches reference
npm run generate:verify  # both in one step
```

## What Happens During `./fablo-fabricx.sh up`

1. Restores any leftover backups from a previous crashed run (safety check)
2. Generates all config files from `schema/fablo-config-fabricx.json`
3. Deploys generated `core.yaml` and `routing-config.yaml` to Fabric-X (backing up originals as `.bak`)
4. Creates Docker network (`fabric_test`)
5. Starts `committer-test-node` (orderer + committer + DB)
6. Creates `token_namespace` on the ledger
7. Starts all FSC nodes (issuer, endorser1, endorser2, owner1, owner2)
8. Waits for all health checks to pass
9. Initializes the endorser
10. Prints endpoint URLs

## What Happens During `./fablo-fabricx.sh test`

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
├── fablo-fabricx.sh          # Network lifecycle manager (generate → deploy → start)
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
