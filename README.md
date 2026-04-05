# Fabric-X Integration into Fablo — Proof of Concept

**Author:** Ritesh Pandit [@Slambot01](https://github.com/Slambot01)
**Mentorship Issue:** [LF-Decentralized-Trust-Mentorships #83](https://github.com/LF-Decentralized-Trust-Mentorships/mentorship-program/issues/83)
**Fablo Issue:** [hyperledger-labs/fablo #611](https://github.com/hyperledger-labs/fablo/issues/611)

## Purpose

This POC maps how Fablo's generation pipeline extends to support Fabric-X's
decomposed FSC (Fabric Smart Client) architecture. Built from direct analysis
of `fabric-x/samples/tokens/` source files.

## Architecture

In Fabric-X, the monolithic peer is replaced by an FSC overlay:

```
committer-test-node (external infrastructure)
┌──────────┬──────────┬─────────┬─────────┐
│ Orderer  │Committer │ DB      │ Query   │
│  :7050   │   :4001  │  :5433  │  :7001  │
└──────────┴──────────┴─────────┴─────────┘
        ▲  websocket P2P mesh via routing-config.yaml
┌────┴──────┐ ┌────┴──────┐ ┌────┴──────┐
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

| Directory | What It Shows |
|-----------|--------------|
| `docs/` | Architecture mapping, codebase analysis, implementation plan |
| `schema/` | Proposed fablo-config.json extensions + TypeScript types |
| `generated/` | Hand-crafted files showing what Fablo would output |
| `templates/` | Prototype EJS templates for the generation engine |

Source references are noted inline. All values derived from
`fabric-x/samples/tokens/` unless otherwise noted.
