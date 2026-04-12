#!/bin/bash
cd ~/lfdt-project/fablo-fork
node -e '
const { Validator } = require("jsonschema");
const schema = require("./docs/schema.json");
const config = {
  "$schema": "https://github.com/hyperledger-labs/fablo/releases/download/2.5.0/schema.json",
  global: { fabricVersion: "2.5.0", tls: true, peerDevMode: false },
  orgs: [{
    organization: { name: "Org1", mspName: "Org1MSP", domain: "org1.example.com" },
    ca: { prefix: "ca", db: "sqlite" },
    orderers: [{ groupName: "group1", prefix: "orderer", type: "raft", instances: 3 }],
    peer: { prefix: "peer", instances: 2, db: "LevelDb" },
  }],
  channels: [{ name: "mychannel", orgs: [{ name: "Org1", peers: ["peer0"] }] }],
  chaincodes: [{ name: "mycc", version: "1.0", lang: "golang", channel: "mychannel", privateData: [] }],
  hooks: {},
};
const v = new Validator();
const result = v.validate(config, schema);
if (result.errors.length > 0) {
  result.errors.forEach(e => console.log(e.property, ":", e.message));
} else {
  console.log("VALID");
}
'
