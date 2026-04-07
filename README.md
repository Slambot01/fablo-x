# Fabric-X Integration into Fablo — Proof of Concept

**Author:** Ritesh Pandit [@Slambot01](https://github.com/Slambot01)  
**Mentorship Issue:** [LF-Decentralized-Trust-Mentorships #83](https://github.com/LF-Decentralized-Trust-Mentorships/mentorship-program/issues/83)  
**Fablo Issue:** [hyperledger-labs/fablo #611](https://github.com/hyperledger-labs/fablo/issues/611)  

## Purpose

This POC maps how Fablo's generation pipeline extends to support Fabric-X's
decomposed FSC (Fabric Smart Client) architecture. Built from direct analysis
of `fabric-x/samples/tokens/` source files.

**This is a fully executable prototype, not just static files.** It programmatically generates Fabric-X configurations from a schema using EJS templates and strictly verifies them line-by-line against hand-crafted ground truth samples.

## Running the Config Generator

You can run the generation tool built into this POC to see exactly how Fablo will construct the Docker Compose and node configurations for Fabric-X dynamically:

```bash
# 1. Install TypeScript and EJS dependencies
npm install

# 2. Generates files and perfectly verifies against ground truth
npm run generate:verify
```

### Expected Output

```plaintext
> fablo-fabricx-generator@1.0.0 generate:verify
> npm run generate && npm run verify

> fablo-fabricx-generator@1.0.0 generate
> ts-node src/generate.ts

Starting Fabric-X configuration generation...
 ✓ Generated docker-compose.yml
 ✓ Generated conf/endorser1/core.yaml
 ✓ Generated conf/endorser1/routing-config.yaml
 ✓ Generated conf/endorser2/core.yaml
 ✓ Generated conf/endorser2/routing-config.yaml
Generation completed successfully!

> fablo-fabricx-generator@1.0.0 verify
> ts-node src/verify.ts

Verifying generated outputs against ground truth...
 ✓ MATCH: conf/endorser1/core.yaml
 ✓ MATCH: conf/endorser1/routing-config.yaml
 ✓ MATCH: conf/endorser2/core.yaml
 ✓ MATCH: conf/endorser2/routing-config.yaml
 ✓ MATCH: docker-compose.yml

✅ Verification passed! All generated files perfectly match the ground truth.
```

### Generator Scripts

- `npm run generate`: Executed via `src/generate.ts`. Parses the Fablo schema extensions in `schema/fablo-config-fabricx.json`, injects context into EJS templates inside `templates/`, and dynamically outputs the Docker compose network and FSC nodes logic inside `generated-output/`.
- `npm run verify`: Executed via `src/verify.ts`. Systematically traverses every output file in `generated-output/` and compares it character-by-character to the hand-crafted `generated/` reference root, aborting on any mismatches.

## Architecture

In Fabric-X, the monolithic peer is replaced by an FSC overlay:

```
committer-test-node (external infrastructure)
┌──────────┬──────────┬─────────┬─────────┐
│ Orderer  │Committer │ DB      │ Query   │
│  :7050   │   :4001  │  :5433  │  :7001  │
└──────────┴──────────┴─────────┴─────────┘
                    ▲  websocket P2P mesh via routing-config.yaml
┌───────────┐ ┌─────┴─────┐ ┌───────────┐
│ endorser1 │ │ issuer    │ │ owner1    │
│ Org1MSP   │ │ Org1MSP   │ │ Org1MSP   │
│ API:9300  │ │ API:9100  │ │ API:9500  │
│ P2P:9301  │ │ P2P:9101  │ │ P2P:9501  │
└───────────┘ └───────────┘ └───────────┘
```

Key differences from classic Fabric:
- FSC core.yaml uses `fsc.id`, `fsc.p2p`, `fabric.default.driver: fabricx`
- P2P mesh via websocket, routed through `routing-config.yaml`
- committer-test-node is started separately, FSC nodes join external `fabric_test` network
- Endorser images build from context with `PLATFORM=fabricx` build tag
- crypto-config.yaml requires `Hostname: SC` for sidecar identity

## Design Decision: Self-Contained Compose

In real Fabric-X, the committer-test-node runs as separate infrastructure and
FSC nodes connect via an external Docker network (`fabric_test`). This POC
includes the committer-test-node in the same compose file because Fablo's
value proposition is single-command deployment (`fablo up`). This is a
deliberate design choice, not an oversight. The `SC_SIDECAR_*` env vars are
derived from the committer-test-node Docker image's configuration interface
(see `fabric-x-committer` repo).

## Contents

| Directory / File | What It Shows |
|-----------|--------------|
| `docs/` | Architecture mapping ([architecture-mapping.md](docs/architecture-mapping.md)) and codebase analysis ([fablo-codebase-changes.md](docs/fablo-codebase-changes.md)) |
| `schema/` | Schema extensions ([fablo-config-fabricx.json](schema/fablo-config-fabricx.json)) and Typings ([FabloConfigJson.fabricx.ts](schema/FabloConfigJson.fabricx.ts)) |
| `templates/` | Source EJS prototypes: [docker-compose-fabricx.ejs](templates/docker-compose-fabricx.ejs), [fsc-core-yaml.ejs](templates/fsc-core-yaml.ejs), [routing-config.ejs](templates/routing-config.ejs) |
| `generated/` | Ground Truth reference: [docker-compose.yml](generated/docker-compose.yml), [core.yaml](generated/conf/endorser1/core.yaml), [routing-config.yaml](generated/conf/endorser1/routing-config.yaml), [fabricx-up.sh](generated/scripts/fabricx-up.sh) |
| `generated-output/` | Dynamic output built locally running `npm run generate` |
| `src/` | Generator code: [generate.ts](src/generate.ts) handles config scaffolding, while [verify.ts](src/verify.ts) enforces identical output rendering. |
| `package.json` / `tsconfig.json` | Local tooling config for the Typescript executable. |

Source references are noted inline. All values derived from
`fabric-x/samples/tokens/` unless otherwise noted.
