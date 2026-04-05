# Fabric-X Integration — Phased Implementation Plan

## Overview

12-week plan to integrate Fabric-X support into Fablo.
Each phase has a concrete, verifiable milestone.

## Phase 1: Foundation (Weeks 1-3)

**Goal:** Schema extension + validation + tooling setup

### Deliverables
- Extend `FabloConfigJson.ts` with Fabric-X types
  - `engine: "fabric-x"` flag in GlobalJson
  - `CommitterJson` interface with SC_SIDECAR_* env var mapping
  - `FscNodeJson` interface with fsc.id, p2p port, driver
  - `committers[]` and `endorsers[]` arrays in OrgJson
- Add validation for Fabric-X topology
  - Minimum 1 committer-test-node per network
  - Minimum 1 endorser per org
  - Unique P2P ports across all FSC nodes
  - engine === "fabric-x" blocks peers[] and orderers[]
- Build Fabric-X tools image
  - configtxgen, cryptogen, fxconfig from Fabric-X Dockerfile
  - Base image: registry.access.redhat.com/ubi9/ubi-minimal:9.6
- Unit tests for all new validators

**Milestone:** `fablo validate` accepts and validates a Fabric-X config

---

## Phase 2: Committer-Test-Node Infrastructure (Weeks 4-6)

**Goal:** Generate working committer sidecar with valid crypto

### Deliverables
- Docker Compose template for committer-test-node
  - Image: ghcr.io/hyperledger/fabric-x-committer-test-node:0.1.7
  - All SC_SIDECAR_*, SC_ORDERER_*, SC_QUERY_SERVICE_* env vars
  - Port mappings: 4001, 7050, 7001, 5433, 2110, 2114, 2117
  - Volume mounts for crypto/ and sc-genesis-block.proto.bin
- Crypto material generation script
  - crypto-config.yaml with Hostname: SC entries
  - Using Fabric-X custom cryptogen binary
- Channel artifact generation script
  - configtx.yaml with V2_0+V2_5 capabilities and etcdraft
  - Using Fabric-X custom configtxgen
  - Outputs sc-genesis-block.proto.bin (not standard genesis.block)
- Startup script with health check on :4001

**Milestone:** `fablo up` boots a committer-test-node with valid crypto material

---

## Phase 3: FSC Endorser Node Support (Weeks 7-9)

**Goal:** Generate FSC endorser nodes that connect to the committer

### Deliverables
- FSC core.yaml template per node
  - fsc.id, fsc.identity (cert + key paths)
  - fsc.p2p (listenAddress, type: websocket, routing-config path)
  - fsc.persistences (sqlite datasource)
  - fsc.endpoint.resolvers (all mesh participants with cert paths)
  - fabric.default (driver: fabricx, msps, peers, queryService, channels)
- routing-config.yaml template per node
  - All FSC nodes listed by logical name to host:p2p_port
  - Generated from fablo-config.json network topology
- Docker Compose entries for endorser nodes
  - build: context with NODE_TYPE build arg
  - API port mapping (external:9000 internal)
  - P2P port mapping (direct)
  - Volume mount for ./conf/endorserN:/conf
  - depends_on: committer-test-node
- fxconfig namespace registration in startup script
  - fxconfig namespace create token_namespace
  - Poll until fxconfig namespace list confirms visible

**Milestone:** `fablo up` boots a complete Fabric-X network (committer + endorsers connected)

---

## Phase 4: Polish + E2E Tests (Weeks 10-12)

**Goal:** Production-ready, tested, documented integration

### Deliverables
- E2E test suite for Fabric-X networks
  - e2e-network/fabricx/test-01-simple.sh
  - Snapshot tests for generated files
- `fablo init` Fabric-X template
  - Sensible defaults for single-org network
  - Correct image versions pinned
- Documentation
  - Usage guide for Fabric-X mode
  - Troubleshooting common startup failures
- CI integration
  - GitHub Actions workflow for Fabric-X e2e tests
- Optional: Token layer support (issuer/owner node generation)
- PR review, feedback incorporation, merge into Fablo main

**Milestone:** Fabric-X support merged into Fablo with passing CI

---

## Risk Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| No pre-built endorser images | High (confirmed) | High | Build from context, propose image publishing to Fabric-X team |
| FSC core.yaml schema changes | Medium | High | Pin to 0.1.7, add version check in validator |
| committer-test-node deprecated | Low | Medium | Phase 3 provides decomposed service fallback |
| Fabric-X API breaks between versions | Medium | Medium | Watch fabric-x repo releases, abstract version handling |
| Token layer complexity blocks delivery | Low | Low | Mark as optional Phase 4, not a blocker for core milestone |

## Success Criteria

- `fablo up` with engine: "fabric-x" boots a running network
- `fablo validate` catches invalid Fabric-X configurations with helpful messages
- All existing docker/kubernetes tests still pass (no regression)
- E2E test confirms endorser can connect to committer sidecar
- PR merged into hyperledger-labs/fablo main branch
