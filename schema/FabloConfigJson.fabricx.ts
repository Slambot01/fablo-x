/**
 * Proposed type extensions for Fabric-X support in Fablo.
 * Based on analysis of fabric-x/samples/tokens/ source files.
 *
 * These types extend the existing Fablo types:
 *   import { CaJson, PeerJson, OrdererJson } from './FabloConfigJson';
 */

// -- Existing Fablo types referenced but not redefined here --
// CaJson, PeerJson, OrdererJson from src/types/FabloConfigJson.ts

interface GlobalJsonExtended {
  fabricVersion: string;
  engine?: "fabric" | "fabric-x";
  tls: boolean;
  fabricXImages?: {
    committerTestNode: string;
    toolsBaseImage: string;
  };
}

interface CommitterPortsJson {
  sidecar: number;      // default 4001
  orderer: number;      // default 7050
  queryService: number; // default 7001
  database: number;     // default 5433
}

interface CommitterSidecarJson {
  channelId: string;        // SC_SIDECAR_ORDERER_CHANNEL_ID
  blockSize: number;        // SC_ORDERER_BLOCK_SIZE
  signedEnvelopes: boolean; // SC_SIDECAR_ORDERER_SIGNED_ENVELOPES
  mspId: string;            // SC_SIDECAR_ORDERER_IDENTITY_MSP_ID
  // mspDir is computed: /root/config/crypto/peerOrganizations/{domain}/peers/SC.{domain}/msp
}

interface CommitterLoggingJson {
  sidecar: string;
  queryService: string;
  coordinator: string;
  orderer: string;
  vc: string;
  verifier: string;
}

interface CommitterJson {
  name: string;
  mode: "bundled";
  ports: CommitterPortsJson;
  sidecar: CommitterSidecarJson;
  logging: CommitterLoggingJson;
}

interface FscPortsJson {
  api: number; // maps to container 9000
  p2p: number; // unique per node, exposed not published
}

interface FscConfigJson {
  id: string;               // fsc.id in core.yaml
  p2pListenAddress: string; // fsc.p2p.listenAddress
  driver: "fabricx";        // fabric.default.driver
}

interface FscDbJson {
  type: "sqlite";
  datasource: string;
}

interface FscNodeJson {
  name: string;
  nodeType: "endorser" | "issuer" | "owner";
  ports: FscPortsJson;
  fsc: FscConfigJson;
  db: FscDbJson;
}

interface OrgJsonExtended {
  organization: { name: string; domain: string; mspName: string };
  ca?: any;       // CaJson from existing Fablo types
  peers?: any[];  // PeerJson[] — classic Fabric only
  orderers?: any[]; // OrdererJson[] — classic Fabric only
  committers?: CommitterJson[];  // Fabric-X only
  endorsers?: FscNodeJson[];     // Fabric-X only
}

// Validation rules:
// 1. engine === "fabric-x" -> must have committers[] and endorsers[]
// 2. engine === "fabric-x" -> must NOT have peers[] or orderers[]
// 3. All P2P ports must be unique across all FSC nodes
// 4. crypto-config.yaml must include Hostname: SC for sidecar certs
// 5. endorsers in different orgs must have different mspID
// 6. Exactly one committer-test-node per network (mode: bundled)
// 7. Channel name must match across schema, core.yaml, and SC_SIDECAR config

export {
  GlobalJsonExtended,
  CommitterJson,
  CommitterPortsJson,
  CommitterSidecarJson,
  CommitterLoggingJson,
  FscNodeJson,
  FscPortsJson,
  FscConfigJson,
  FscDbJson,
  OrgJsonExtended,
};
