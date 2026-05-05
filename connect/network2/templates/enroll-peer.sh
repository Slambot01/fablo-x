#!/bin/bash
set -e
export PATH="$HOME/lfdt-project/fablo-fork/bin:$PATH"

CA_URL=$(jq -r '.orgs[0].ca.url' ./fablo-connect-config.json)
CA_TLS_CERT=$(jq -r '.orgs[0].ca.tlsCACertPath' ./fablo-connect-config.json)

export FABRIC_CA_CLIENT_HOME=$(pwd)/generated/crypto/peer1.org1.example.com
ADMIN_HOME=$(pwd)/generated/crypto/admin

# Enroll admin
fabric-ca-client enroll \
  -u $(echo $CA_URL | sed 's|https://|https://admin:adminpw@|') \
  --tls.certfiles $CA_TLS_CERT \
  --caname ca.org1.example.com \
  -M $ADMIN_HOME/msp

# Register peer1
fabric-ca-client register \
  --id.name peer1.org1.example.com \
  --id.secret peer1pw \
  --id.type peer \
  --tls.certfiles $CA_TLS_CERT \
  --caname ca.org1.example.com \
  --mspdir $ADMIN_HOME/msp || echo "Identity already registered"

# Enroll peer1
fabric-ca-client enroll \
  -u $(echo $CA_URL | sed 's|https://|https://peer1.org1.example.com:peer1pw@|') \
  --tls.certfiles $CA_TLS_CERT \
  --caname ca.org1.example.com \
  -M $FABRIC_CA_CLIENT_HOME/msp

# Enable admincerts since NodeOUs are not enabled
mkdir -p $FABRIC_CA_CLIENT_HOME/msp/admincerts
cp /home/ritesh/lfdt-project/Fablo-fabricx/connect/network1/fablo-target/fabric-config/crypto-config/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp/signcerts/Admin@org1.example.com-cert.pem $FABRIC_CA_CLIENT_HOME/msp/admincerts/

# Enroll peer1 TLS
fabric-ca-client enroll \
  -u $(echo $CA_URL | sed 's|https://|https://peer1.org1.example.com:peer1pw@|') \
  --enrollment.profile tls \
  --csr.hosts peer1.org1.example.com,localhost \
  --tls.certfiles $CA_TLS_CERT \
  --caname ca.org1.example.com \
  -M $FABRIC_CA_CLIENT_HOME/tls-msp

# Rename TLS files to match docker-compose requirements
mv $FABRIC_CA_CLIENT_HOME/tls-msp/keystore/*_sk \
   $FABRIC_CA_CLIENT_HOME/tls-msp/server.key
mv $FABRIC_CA_CLIENT_HOME/tls-msp/signcerts/cert.pem \
   $FABRIC_CA_CLIENT_HOME/tls-msp/server.crt
mv $FABRIC_CA_CLIENT_HOME/tls-msp/tlscacerts/*.pem \
   $FABRIC_CA_CLIENT_HOME/tls-msp/ca.crt

echo "peer1 enrolled successfully"
echo "MSP path: $FABRIC_CA_CLIENT_HOME"
