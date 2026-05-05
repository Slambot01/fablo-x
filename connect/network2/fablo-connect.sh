#!/bin/bash
set -e
export PATH="$HOME/lfdt-project/fablo-fork/bin:$PATH"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

generate() {
  mkdir -p $SCRIPT_DIR/generated
  cp $SCRIPT_DIR/templates/docker-compose.peer.yml $SCRIPT_DIR/generated/docker-compose.yml
  DOCKER_NETWORK_NAME=$(jq -r '.network.dockerNetworkName' $SCRIPT_DIR/fablo-connect-config.json)
  sed -i "s|DOCKER_NETWORK_NAME|$DOCKER_NETWORK_NAME|g" $SCRIPT_DIR/generated/docker-compose.yml
  echo "Generated docker-compose.yml"
}

up() {
  generate
  echo "=== fablo connect: starting peer1 ==="
  bash $SCRIPT_DIR/templates/enroll-peer.sh
  docker compose -f $SCRIPT_DIR/generated/docker-compose.yml up -d
  echo "Waiting for peer1 to be healthy..."
  for i in {1..15}; do
    if docker ps | grep -q "peer1.org1.example.com"; then
      echo "peer1 is running."
      break
    fi
    sleep 2
  done
  sleep 5
  bash $SCRIPT_DIR/templates/join-channel.sh
  echo "=== peer1 is up and joined my-channel1 ==="
}

down() {
  docker compose -f $SCRIPT_DIR/generated/docker-compose.yml down
  echo "=== peer1 stopped ==="
}

status() {
  docker ps | grep peer1 || echo "peer1 not running"
  docker exec peer1.org1.example.com peer channel list 2>/dev/null \
      || echo "cannot reach peer1"
}

test_network() {
  if docker ps | grep -q peer1.org1.example.com; then
    if docker exec peer1.org1.example.com peer channel list | grep -q my-channel1; then
      echo "PASS: peer1 joined my-channel1 successfully"
    else
      echo "FAIL: channel not joined"
    fi
  else
    echo "FAIL: peer1 not running"
  fi
}

usage() {
  echo "Usage: ./fablo-connect.sh [up|down|status|test|generate]"
}

case "$1" in
  up) up ;;
  down) down ;;
  status) status ;;
  test) test_network ;;
  generate) generate ;;
  *) usage ;;
esac
