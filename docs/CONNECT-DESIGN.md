# fablo connect — Design Document

**Issue:** [#619](https://github.com/hyperledger-labs/fablo/issues/619)
**Status:** POC validated
**Date:** 2026-05-05

## Goal

Allow a new peer to join an **already-running** Fablo network by enrolling
with the existing CA, fetching the channel genesis block from the orderer,
and joining the channel — all driven from a single `fablo-connect-config.json`.

## Architecture

```
network1 (existing Fablo network)
  ┌──────┐  ┌──────────┐  ┌──────┐
  │  CA   │  │ Orderer  │  │ peer0│
  └──┬───┘  └────┬─────┘  └──────┘
     │           │
     │    Docker network (shared)
     │           │
network2 (fablo connect)
     │           │
  enroll      fetch block
     │           │
  ┌──▼───────────▼──┐
  │     peer1       │
  └─────────────────┘
```

## POC Structure

```
connect/
├── docs/
├── network1/                      # source network (standard Fablo)
│   ├── fablo-config.json
│   └── fablo-target/              # generated artifacts
├── network2/                      # connected peer
│   ├── fablo-connect-config.json  # connect-specific schema
│   ├── fablo-connect.sh           # lifecycle: up / down / status / test
│   ├── templates/
│   │   ├── docker-compose.peer.yml
│   │   ├── enroll-peer.sh
│   │   └── join-channel.sh
│   └── generated/                 # runtime artifacts
│       ├── crypto/
│       ├── docker-compose.yml
│       └── my-channel1.block
```

## Implementation Findings

### Fix 1: Docker network isolation

**Problem:** peer1 cannot reach CA, orderer, or peer0.
**Root cause:** peer1 starts on a default bridge network; network1 uses a
Fablo-generated network name.
**Solution:** Add `networks: { <name>: { external: true } }` to the peer
compose file and inject `dockerNetworkName` from the connect config.

### Fix 2: CA TLS certificate path

**Problem:** `fabric-ca-client enroll` fails with x509 certificate signed
by unknown authority.
**Root cause:** The CA is using TLS, but the client does not trust the CA's
self-signed TLS certificate.
**Solution:** Pass `--tls.certfiles` pointing to the CA's TLS cert from
network1's crypto-config directory.

### Fix 3: CA enrollment URL scheme

**Problem:** Enrollment fails with connection refused on port 80.
**Root cause:** URL uses `http://` but the CA listens on HTTPS when TLS
is enabled.
**Solution:** Use `https://admin:adminpw@localhost:7020` — scheme must match
the CA's TLS setting.

### Fix 4: Admin MSP for peer registration

**Problem:** `fabric-ca-client register` fails with authorization error.
**Root cause:** The register command requires an already-enrolled admin
identity, but `--mspdir` was not set.
**Solution:** Enroll admin first, then pass `--mspdir $ADMIN_HOME/msp` to
the register command.

### Fix 5: NodeOUs vs admincerts

**Problem:** peer1 starts but cannot validate admin signatures.
**Root cause:** Fablo-generated CAs do not enable NodeOUs by default, so
the peer falls back to the `admincerts` folder which was empty.
**Solution:** Copy the network1 Admin signcert into
`peer1/msp/admincerts/Admin@org1.example.com-cert.pem`.

### Fix 6: TLS key/cert file naming

**Problem:** peer1 container exits immediately — cannot find TLS certs.
**Root cause:** `fabric-ca-client enroll --enrollment.profile tls` puts
certs in `tls-msp/signcerts/cert.pem` and keys in
`tls-msp/keystore/<hash>_sk`, but the peer expects `server.crt`,
`server.key`, and `ca.crt` at fixed paths.
**Solution:** Rename after enrollment:
```
mv tls-msp/keystore/*_sk         tls-msp/server.key
mv tls-msp/signcerts/cert.pem    tls-msp/server.crt
mv tls-msp/tlscacerts/*.pem      tls-msp/ca.crt
```

### Fix 7: Orderer TLS hostname override

**Problem:** `peer channel fetch` fails with x509 certificate validation.
**Root cause:** The orderer's TLS cert has SAN
`orderer0.group1.org1.example.com` but we connect via `localhost`.
**Solution:** Add `--ordererTLSHostnameOverride orderer0.group1.org1.example.com`
to all orderer-facing CLI commands.

### Fix 8: Gossip bootstrap address

**Problem:** peer1 logs flooded with gossip connection errors.
**Root cause:** `CORE_PEER_GOSSIP_BOOTSTRAP` was set to peer1's own address.
**Solution:** Set gossip bootstrap to peer0's advertised address:
`peer0.org1.example.com:7021`.

### Fix 9: Idempotent peer registration

**Problem:** Second run of `fablo-connect.sh up` hits Error Code 74 —
Identity already registered.
**Root cause:** CA state persists across connect/disconnect cycles; the
identity registered on the first run still exists in the CA database.
**Solution:** Trap Error Code 74 and continue:
```bash
fabric-ca-client register ... || echo "Identity already registered"
```
**Implication:** `fablo connect up` must be idempotent — check if identity
exists before registering.

## Schema Gaps Summary

Fields required by `fablo connect` that are **not** in the current
`fablo-config.json` schema:

| Field | Proposed Key | Failure Without It |
|-------|-------------|--------------------|
| Docker network name | `network.dockerNetworkName` | peer starts on wrong network |
| CA TLS cert path | `ca.tlsCACertPath` | enrollment fails (x509 unknown authority) |
| Orderer URL | `orderer.url` | cannot fetch channel block |
| Orderer TLS cert | `orderer.tlsCACertPath` | orderer connection fails (TLS) |
| Admin MSP path | `ca.adminMspPath` | peer registration unauthorized |
| CA credentials | `ca.adminUsername` + `ca.adminPassword` | enrollment fails |
| TLS hostname | `orderer.hostnameOverride` | x509 validation fails |

## Connect Config Schema

```json
{
  "global": {
    "fabricVersion": "2.5.9",
    "tls": true
  },
  "network": {
    "dockerNetworkName": "<from fablo network>"
  },
  "orgs": [{
    "organization": { "name": "Org1", "domain": "org1.example.com", "mspName": "Org1MSP" },
    "ca": {
      "url": "https://localhost:7020",
      "tlsCACertPath": "<path to ca cert from network1>",
      "adminMspPath": "<path to Admin MSP from network1>"
    },
    "orderer": {
      "url": "localhost:7030",
      "tlsCACertPath": "<path to orderer TLS cert from network1>"
    },
    "peer": { "instances": 1 }
  }],
  "channels": [{
    "name": "my-channel1",
    "orgs": [{ "name": "Org1", "peers": ["peer1"] }]
  }]
}
```

## Lifecycle Commands

| Command | Action |
|---------|--------|
| `fablo-connect.sh up` | generate → enroll → start peer → join channel |
| `fablo-connect.sh down` | stop and remove peer container |
| `fablo-connect.sh status` | show peer status and channel membership |
| `fablo-connect.sh test` | verify peer joined the target channel |
| `fablo-connect.sh generate` | generate docker-compose only (no start) |

## Validation Criteria (POC)

- [x] peer1 container starts and stays healthy
- [x] peer1 joins my-channel1 via orderer
- [x] `peer channel list` shows my-channel1
- [x] Idempotent: second `up` succeeds without error
- [ ] Chaincode query from peer1 (deferred to integration phase)
