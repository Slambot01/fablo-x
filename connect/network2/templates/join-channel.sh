#!/bin/bash
set -e
export PATH="$HOME/lfdt-project/fablo-fork/bin:$PATH"

ORDERER_URL=$(jq -r '.orgs[0].orderer.url' ./fablo-connect-config.json)
ORDERER_TLS_CERT=$(jq -r '.orgs[0].orderer.tlsCACertPath' ./fablo-connect-config.json)

export FABRIC_CFG_PATH=$HOME/lfdt-project/fablo-fork/config

export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_LOCALMSPID=Org1MSP
export CORE_PEER_ID=peer1.org1.example.com
export CORE_PEER_ADDRESS=localhost:7051
export CORE_PEER_TLS_ROOTCERT_FILE=$(pwd)/generated/crypto/peer1.org1.example.com/tls-msp/ca.crt
export CORE_PEER_MSPCONFIGPATH=/home/ritesh/lfdt-project/Fablo-fabricx/connect/network1/fablo-target/fabric-config/crypto-config/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp

peer channel fetch oldest \
  ./generated/my-channel1.block \
  -c my-channel1 \
  -o $ORDERER_URL \
  --ordererTLSHostnameOverride orderer0.group1.org1.example.com \
  --tls \
  --cafile $ORDERER_TLS_CERT

peer channel join -b ./generated/my-channel1.block

peer channel list

echo "peer1 joined my-channel1 successfully"
