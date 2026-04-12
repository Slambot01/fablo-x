# Architecture Mapping: Classic Fabric → Fabric-X

All findings based on direct analysis of Fabric-X source:
- samples/tokens/compose.yml
- samples/tokens/conf/endorser1/core.yaml
- samples/tokens/conf/endorser1/routing-config.yaml
- samples/tokens/crypto-config.yaml
- samples/tokens/configtx.yaml

## Service Mapping

| Classic Fabric | Fabric-X Equivalent | Image | Notes |
|----------------|---------------------|-------|-------|
| `hyperledger/fabric-peer` | FSC Endorser Node | Built from context (NODE_TYPE=endorser) | NOT a pre-built image |
| `hyperledger/fabric-orderer` | Inside committer-test-node | `ghcr.io/hyperledger/fabric-x-committer-test-node:0.1.7` | Port 7050 |
| `hyperledger/fabric-ca` | Standard CA | `hyperledger/fabric-ca` | Unchanged |
| `hyperledger/fabric-tools` | Custom tools from Fabric-X Dockerfile | Built from source | configtxgen, cryptogen, fxconfig, idemixgen |
| N/A | Committer (inside sidecar) | Part of committer-test-node | Port 4001 |
| N/A | Query Service (inside sidecar) | Part of committer-test-node | Port 7001 |
| N/A | Issuer (FSC node) | Built from context (NODE_TYPE=issuer) | Token issuance |
| N/A | Owner (FSC node) | Built from context (NODE_TYPE=owner) | Token ownership |

## Configuration File Mapping

| Classic Fabric | Fabric-X | Key Difference |
|----------------|----------|----------------|
| `core.yaml` (CORE_PEER_* config) | `core.yaml` (FSC config) | Completely different schema — fsc.id, fsc.p2p, fsc.persistences |
| N/A | `routing-config.yaml` | Maps route aliases to host:port websocket endpoints |
| `configtx.yaml` | `configtx.yaml` | Similar but V2_0+V2_5 capabilities, etcdraft |
| `crypto-config.yaml` | `crypto-config.yaml` | Must include Hostname: SC for sidecar certs |
| N/A | `zkatdlognoghv1_pp.json` | Zero-knowledge proof public parameters (token layer) |

## Environment Variable Mapping

| Classic Fabric | Fabric-X | Purpose |
|----------------|----------|---------|
| `CORE_PEER_ID` | `fsc.id` in core.yaml | Node identity |
| `CORE_PEER_ADDRESS` | `fsc.p2p.listenAddress: /ip4/0.0.0.0/tcp/PORT` | P2P listen address |
| `CORE_PEER_GOSSIP_BOOTSTRAP` | `routing-config.yaml` routes | Peer discovery |
| `CORE_PEER_LOCALMSPID` | `SC_SIDECAR_ORDERER_IDENTITY_MSP_ID` | MSP identity (committer only) |
| `CORE_PEER_TLS_ENABLED` | `fabric.default.tls.enabled` in core.yaml | TLS config |
| N/A | `SC_SIDECAR_ORDERER_CHANNEL_ID=mychannel` | Channel for sidecar |
| N/A | `SC_SIDECAR_ORDERER_SIGNED_ENVELOPES=true` | Envelope signing |
| N/A | `SC_ORDERER_BLOCK_SIZE=1` | Block size config |
| N/A | `SC_QUERY_SERVICE_SERVER_ENDPOINT=:7001` | Query service port |
| N/A | `SC_SIDECAR_LOGGING_LEVEL=DEBUG` | Per-component logging |

## Port Assignments (from actual compose.yml)

| Service | External Port | Purpose |
|---------|--------------|---------|
| committer-test-node | 4001 | Committer sidecar (FSC nodes connect here) |
| committer-test-node | 7050 | Orderer |
| committer-test-node | 7001 | Query service |
| committer-test-node | 5433 | Database |
| committer-test-node | 2110 | Internal service |
| committer-test-node | 2114 | Internal service |
| committer-test-node | 2117 | Internal service |
| endorser1 | 9300 (maps to 9000) | FSC API |
| endorser1 | 9301 | P2P websocket |
| issuer | 9100 (maps to 9000) | FSC API |
| issuer | 9101 | P2P websocket |
| owner1 | 9500 (maps to 9000) | FSC API |
| owner1 | 9501 | P2P websocket |
| owner2 | 9600 (maps to 9000) | FSC API |
| owner2 | 9601 | P2P websocket |

## Communication Pattern Mapping

| Interaction | Classic Fabric | Fabric-X |
|-------------|---------------|----------|
| Client to endorser | gRPC :7051 | gRPC :9300 (FSC API) |
| Endorser to endorser | gRPC gossip | Websocket P2P via routing-config.yaml |
| Endorser to orderer | gRPC :7050 | Via committer-sidecar :4001 |
| Endorser to ledger query | Internal (same process) | committer-queryservice :7001 |
| Node discovery | Gossip bootstrap | Explicit routing-config.yaml entries |

## FSC core.yaml Structure (from actual endorser1/core.yaml)
```yaml
logging:
  spec: info

fsc:
  id: endorser1
  identity:
    cert:
      file: ./keys/node.crt
    key:
      file: ./keys/node.key
  p2p:
    listenAddress: /ip4/0.0.0.0/tcp/9301
    type: websocket
    opts:
      routing:
        path: ./routing-config.yaml
  persistences:
    default:
      type: sqlite
      opts:
        dataSource: file:./data/fts.sqlite
  endpoint:
    resolvers:
      - name: endorser1
        identity:
          id: endorser1
          path: ./keys/nodes/endorser1.crt
        addresses:
          P2P: endorser1.example.com:9301

fabric:
  enabled: true
  default:
    driver: fabricx
    msps:
      - id: endorser
        mspType: bccsp
        mspID: Org1MSP
        path: ./keys/fabric/endorser
    tls:
      enabled: false
    peers:
      - address: committer-sidecar:4001
    queryService:
      - address: committer-queryservice:7001
    channels:
      - name: mychannel
        default: true

token:
  enabled: true
  tms:
    mytms:
      network: default
      channel: mychannel
      namespace: token_namespace
      driver: zkatdlog
```

## routing-config.yaml Structure (from actual file)
```yaml
routes:
  issuer:
    - issuer.example.com:9101
  auditor:
    - auditor.example.com:9201
  endorser1:
    - endorser1.example.com:9301
  endorser2:
    - endorser2.example.com:9401
  owner1:
    - owner1.example.com:9501
  owner2:
    - owner2.example.com:9601
```

Every FSC node gets its own routing-config.yaml listing ALL other nodes
in the mesh. Fablo must generate this per-node based on the network topology
defined in fablo-config.json.

## crypto-config.yaml Key Difference

Classic Fabric crypto-config.yaml defines standard peer hostnames.
Fabric-X must additionally generate SC (sidecar) certificates:
```yaml
PeerOrgs:
  - Name: Org1
    Domain: org1.example.com
    Specs:
      - Hostname: SC        # <-- NEW: sidecar identity cert
      - Hostname: endorser1
      - Hostname: endorser2
```

Without the SC cert, the committer-test-node cannot establish
its MSP identity and will fail to start.
