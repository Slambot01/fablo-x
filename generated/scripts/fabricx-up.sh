#!/bin/bash
# Fablo Fabric-X startup script
# Source reference: fabric-x/samples/tokens/ startup sequence
set -e

SCRIPT_DIR="$(cd "$(dirname "\$0")" && pwd)"
cd "$SCRIPT_DIR/.."

echo "=== Step 1: Generate crypto material ==="
docker run --rm \
  -v "$(pwd)/crypto-config.yaml:/config/crypto-config.yaml" \
  -v "$(pwd)/crypto:/crypto" \
  fabric-x-tools cryptogen generate \
    --config=/config/crypto-config.yaml \
    --output=/crypto

echo "=== Step 2: Generate channel artifacts ==="
docker run --rm \
  -v "$(pwd)/configtx.yaml:/config/configtx.yaml" \
  -v "$(pwd)/crypto:/crypto" \
  fabric-x-tools configtxgen \
    -profile OrgsChannel \
    -channelID mychannel \
    -outputBlock /crypto/sc-genesis-block.proto.bin \
    -configPath /config

echo "=== Step 3: Start committer-test-node ==="
docker compose up -d committer-test-node

echo "=== Step 4: Wait for committer health ==="
echo "Waiting for committer-test-node..."
until docker compose exec committer-test-node nc -z 127.0.0.1 4001 2>/dev/null; do
  sleep 2
  echo "  ...waiting"
done
echo "Committer is healthy."

echo "=== Step 5: Start FSC nodes ==="
docker compose up -d endorser1.org1.example.com endorser2.org2.example.com

echo "=== Step 6: Wait for endorsers ==="
sleep 5

echo "=== Step 7: Register token namespace via fxconfig ==="
docker run --rm \
  --network fabric_test \
  -v "$(pwd)/crypto:/crypto" \
  fabric-x-tools fxconfig namespace create \
    --orderer orderer.example.com:7050 \
    --channel mychannel \
    --namespace token_namespace \
    --mspConfigPath /crypto/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp \
    --mspID Org1MSP

echo "=== Fabric-X network is running ==="
docker compose ps
