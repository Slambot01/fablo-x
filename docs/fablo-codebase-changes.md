# Fablo Codebase — Required Changes for Fabric-X

## Critical Understanding

Fabric-X is NOT a simple swap of Docker images. It introduces:

1. FSC (Fabric Smart Client) overlay — completely different node model
2. Websocket P2P mesh — replacing gRPC gossip
3. Sidecar pattern — committer-test-node bundles orderer+committer+db+query
4. Build-from-context images — endorsers are NOT pre-built images
5. New config schemas — FSC core.yaml is unrelated to Fabric core.yaml
6. Token management — optional but part of the reference samples

## Files That Need Modification

### 1. src/types/FabloConfigJson.ts
Add to GlobalJson:
- engine?: "fabric" | "fabric-x"
- fabricXImages?: { committerTestNode, toolsBaseImage }

Add new interfaces:
- CommitterJson (name, mode, ports, sidecar env vars, logging)
- FscNodeJson (name, nodeType, ports, fsc config, db config)

Add to OrgJson:
- committers?: CommitterJson[]
- endorsers?: FscNodeJson[]

### 2. src/types/FabloConfigExtended.ts
- Mirror the same additions as FabloConfigJson.ts
- Add defaults for Fabric-X image versions

### 3. src/commands/validate/index.ts
New validation methods:
- _validateFabricXTopology()
  - engine === "fabric-x" requires committers[] and endorsers[]
  - engine === "fabric-x" must NOT have peers[] or orderers[]
  - Minimum 1 committer, minimum 1 endorser per org
- _validateFscNodeConfig()
  - Each FSC node must have unique fsc.id
  - All P2P ports must be unique across the network
  - Each endorser routing must reference valid nodes
- _validateFabricXVersion()
  - Warn if fabricXImages.committerTestNode version is not pinned

### 4. src/setup-docker/ — New Templates

docker-compose-fabricx.ejs
- committer-test-node service with all SC_* env vars
- FSC endorser nodes with build-from-context
- Correct port mappings (api port maps to container 9000, p2p direct)
- depends_on: committer-test-node for all FSC nodes

fsc-core-yaml.ejs
- fsc.id, fsc.identity (cert + key paths)
- fsc.p2p (listenAddress, type: websocket, routing path)
- fsc.persistences (sqlite datasource)
- fsc.endpoint.resolvers (per node in mesh)
- fabric.default (driver: fabricx, msps, tls, peers, queryService, channels)
- token section (optional, controlled by flag)

routing-config.ejs
- routes: map of logical name to [host:p2p_port]
- Generated per FSC node listing ALL other mesh participants

### 5. src/setup-docker/ — New Script Templates

fabricx-generate-crypto.sh
- Uses Fabric-X custom cryptogen (not standard)
- crypto-config.yaml must include Hostname: SC entries
- Outputs to ./crypto/ directory

fabricx-generate-channel.sh
- Uses Fabric-X custom configtxgen
- configtx.yaml with V2_0+V2_5 capabilities
- etcdraft orderer type
- Generates sc-genesis-block.proto.bin (not standard genesis.block)

fabricx-up.sh
- Pull/build committer-test-node first
- Start committer-test-node
- Wait for sidecar to be healthy (poll :4001)
- Start FSC endorser nodes
- Run fxconfig namespace create (register namespace with orderer)
- Poll until fxconfig namespace list confirms namespace visible

### 6. src/commands/setup-network/index.ts
- Add fabric-x engine routing alongside existing kubernetes/docker routing
- Route to new SetupFabricX class when engine === "fabric-x"

### 7. src/commands/validate/index.ts — Engine Routing
- Add fabric-x block to _validateEngineSpecificSettings()
- This replaces the existing TODO comment

### 8. src/extend-config/index.ts
- Add Fabric-X defaults (image versions, default ports, default logging levels)

## Files That Stay Unchanged
- CA generation logic (same CA infrastructure)
- Basic CLI structure and Oclif command pattern
- Config file JSON parsing entry point
- TLS certificate handling (Fabric-X also uses TLS)

## New Directory: src/setup-fabricx/

src/setup-fabricx/
├── index.ts                  SetupFabricX class (mirrors SetupDocker)
└── templates/
    ├── docker-compose.ejs    Compose for committer + FSC nodes
    ├── fsc-core-yaml.ejs     Per-node FSC configuration
    └── routing-config.ejs    Per-node P2P mesh routing

## Estimated Scope

| Area | New Files | Modified Files | Effort |
|------|-----------|---------------|--------|
| Types / Schema | 1 | 2 | Small |
| Validation | 0 | 1 | Medium |
| Docker Compose Templates | 1 | 0 | Large |
| FSC Config Templates | 2 | 0 | Large |
| Script Templates | 3 | 0 | Medium |
| Engine Routing | 1 | 2 | Medium |
| Config Defaults | 0 | 1 | Small |
| Tests | 4-5 | 2 | Medium |
| **Total** | **~13** | **~8** | **12 weeks** |
