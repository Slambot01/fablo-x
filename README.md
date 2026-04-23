# Fablo-X

**A one-command bootstrap tool for Fabric-X networks.**

Fablo-X dynamically generates Fabric-X network configurations from a declarative JSON schema, and deploys and manages the full network lifecycle including infrastructure and Fabric Smart Client (FSC) nodes.

## Quick Start

### Prerequisites
- Node.js 18+
- Docker Desktop
- Go 1.24+
- Fabric-X repository cloned at `~/lfdt-project/fabric-x`

### Setup and Verification
```bash
npm install
npm run generate:verify
```

### Full Pipeline execution
```bash
./fablo-x.sh up     # Full pipeline: generates configs, deploys to fabric-x, starts network
./fablo-x.sh test   # Runs full token lifecycle E2E verification
./fablo-x.sh down   # Clean teardown (restores original configs, cleans FSC state)
```

## Pipeline Flow

```text
fablo-config-fabricx.json (schema)
        ↓
npm run generate (EJS templates)
        ↓
generated-output/ (core.yaml, routing-config, docker-compose)
        ↓
fablo-x.sh up (copies configs → fabric-x deployment)
        ↓
Fabric-X network running with GENERATED configs
        ↓
fablo-x.sh test (token lifecycle verification)
        ↓
fablo-x.sh down (restore originals, clean state)
```

## Available Commands

| Command | Description |
|---------|-------------|
| `npm run generate` | Generate configs from schema |
| `npm run verify` | Verify generated matches reference |
| `npm run generate:verify` | Generate + verify |
| `./fablo-x.sh generate` | Standalone generation |
| `./fablo-x.sh up` | Full pipeline: generate → deploy → start |
| `./fablo-x.sh down` | Teardown + restore + clean |
| `./fablo-x.sh test` | Token lifecycle E2E test |
| `./fablo-x.sh status` | Container and health status |

## Architecture

This POC maps the declarative JSON schema approach of Fablo to the decomposed architecture of Fabric-X. Instead of static peers, it scales out Fabric Smart Client (FSC) nodes that interact via a P2P websocket mesh, while utilizing a core committer infrastructure. 

- **committer-test-node**: Handles core Orderer and Committer functions, executing queries.
- **FSC nodes** (issuer, endorser, owner): Lightweight nodes generated based on roles defined in the JSON configuration.
- **Dynamic Networking**: The generator parses node roles, assigns available ports, lists correct websocket P2P routes in `routing-config.yaml`, and prepares `core.yaml` specific configurations.
- **Drivers**: Token architecture uses `zkatdlog` and relies on channel `mychannel`.

## Key Discoveries

During development and testing, several key Fabric-X behavioral details were diagnosed:
- **Channel Mismatch**: The xdev setup path generated an underlying channel named `mychannel`, while ansible references used `arma`. Both the schema and configs were updated to properly align on `mychannel`.
- **Namespace Creation**: Creating a correctly functioning namespace requires utilizing the `channel_admin` MSP path with the `--pk` flag. 
- **FSC State Accumulation**: FSC node data (SQLite databases) persist on disk through host bind-mounts. A standard `docker compose down -v` does not purge them. Leftover UTXO data causes UTXO spending errors (e.g. `[Deleted]: invalid transaction`) on subsequent test runs so the pipeline is fortified to actively wipe these SQLite structures on teardown and initialization.
- **Build Tags**: Correctly compiling the FSC node requires `PLATFORM=fabricx` during the Docker image build.

## Project Structure

```text
├── fablo-x.sh          # Network lifecycle manager
├── src/
│   ├── generate.ts           # Dynamic config generator
│   └── verify.ts             # Output component matching
├── schema/
│   ├── fablo-config-fabricx.json    # Network topology definition
│   └── FabloConfigJson.fabricx.ts   # TypeScript definition mappings
├── templates/
│   ├── docker-compose-fabricx.ejs   # Templates for infrastructure orchestrator
│   ├── fsc-core-yaml.ejs           # FSC node YAML settings
│   └── routing-config.ejs          # Automatic P2P mesh config template
├── generated/                 # Reference base lines
└── docs/
    ├── architecture-mapping.md
    └── evidence/              # Testing evidence
```


## Evidence

The `docs/evidence/` directory contains verified outputs from live Fabric-X deployments:

| File | What It Proves |
|:---|:---|
| `session3-full-bootstrap.txt` | Complete pipeline: clean slate → setup → up (7 containers healthy) → test (all balance assertions passed) → down → repeat cycle |
| `pipeline-e2e-test.txt` | End-to-end trace: generate → deploy → start → token transfers → state cleanup |
| `fabric-x-token-lifecycle.txt` | Full token lifecycle: endorser init → issue 300 EURX to alice → issue 150 EURX to carlos → transfer 50 → verify final balances (alice: 250, carlos: 200) → committer at block 6 |
| `ANALYSIS.md` | Deployment discoveries: channel mismatch, namespace flags, SQLite state persistence |

---

*Built as part of the [LFDT Mentorship 2026](https://github.com/LF-Decentralized-Trust-Mentorships/mentorship-program/issues/83) application — Ritesh Pandit*
