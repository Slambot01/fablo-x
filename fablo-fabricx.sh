#!/bin/bash
set -e

# ============================================================
# Fablo-FabricX Lifecycle Script
# Orchestrates the full Fabric-X token network bootstrap using
# generated configurations from the Fablo-FabricX generator.
#
# Commands:
#   setup    — one-time: install prereqs, crypto, images, keys
#   up       — generate configs → deploy → start network
#   down     — teardown containers, restore configs, clean state
#   test     — run token lifecycle E2E test
#   status   — show container and health status
#   generate — generate configs only (no deploy)
# ============================================================

# -- Colors --
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# -- Paths --
POC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FABRIC_X_DIR="$HOME/lfdt-project/fabric-x/samples/tokens"
GENERATED_DIR="$POC_DIR/generated-output"

# -- Constants --
NODES="issuer endorser1 endorser2 owner1 owner2"

# -- PATH setup (must be before any go/fabric commands) --
export PATH="/usr/local/go/bin:$FABRIC_X_DIR/fabric-samples/bin:$PATH"

# ============================================================
# Utility Functions
# ============================================================

print_banner() {
    echo ""
    echo -e "${CYAN}${BOLD}==========================================${NC}"
    echo -e "${CYAN}${BOLD}  $1${NC}"
    echo -e "${CYAN}${BOLD}==========================================${NC}"
    echo ""
}

print_step() {
    echo -e "${BOLD}[$1] $2${NC}"
}

print_ok() {
    echo -e "  ${GREEN}✓ $1${NC}"
}

print_warn() {
    echo -e "  ${YELLOW}⚠ $1${NC}"
}

print_fail() {
    echo -e "  ${RED}✗ $1${NC}"
}

restore_backups() {
    for node in $NODES; do
        for cfg in core.yaml routing-config.yaml; do
            if [ -f "$FABRIC_X_DIR/conf/$node/$cfg.bak" ]; then
                mv "$FABRIC_X_DIR/conf/$node/$cfg.bak" "$FABRIC_X_DIR/conf/$node/$cfg"
            fi
        done
    done
    if [ -f "$FABRIC_X_DIR/compose.yml.bak" ]; then
        mv "$FABRIC_X_DIR/compose.yml.bak" "$FABRIC_X_DIR/compose.yml"
    fi
}

clean_fsc_data() {
    for node in $NODES; do
        rm -rf "$FABRIC_X_DIR/conf/$node/data/" 2>/dev/null || true
    done
}

check_health() {
    local port=$1
    local name=$2
    if curl -sf "http://localhost:$port/healthz" > /dev/null 2>&1; then
        print_ok "$name (port $port): HEALTHY"
        return 0
    else
        print_fail "$name (port $port): UNHEALTHY"
        return 1
    fi
}

# -- Safety trap: restore on interrupt --
trap 'echo ""; print_warn "Interrupted — restoring original configs..."; restore_backups; exit 1' INT TERM

# ============================================================
# Validate FABRIC_X_DIR
# ============================================================

if [ ! -d "$FABRIC_X_DIR" ]; then
    echo -e "${RED}Error: Fabric-X directory not found: $FABRIC_X_DIR${NC}"
    exit 1
fi

COMMAND="${1:-help}"

# ============================================================
# SETUP Command
# ============================================================

cmd_setup() {
    print_banner "Fablo-FabricX: One-Time Setup"

    # Step 1: Validate environment
    print_step "1/5" "Validating environment..."
    local missing=0
    docker info > /dev/null 2>&1 || { print_fail "Docker is not running"; missing=1; }
    go version > /dev/null 2>&1 || { print_fail "Go is not available"; missing=1; }
    node --version > /dev/null 2>&1 || { print_fail "Node.js is not available"; missing=1; }
    [ $missing -eq 1 ] && { echo -e "${RED}Fix missing dependencies and retry.${NC}"; exit 1; }
    print_ok "Docker, Go, Node.js all available"

    # Step 2: Install Fabric prerequisites
    print_step "2/5" "Checking Fabric prerequisites..."
    if [ -f "$FABRIC_X_DIR/fabric-samples/bin/cryptogen" ]; then
        print_ok "Prerequisites already installed, skipping"
    else
        echo "  Installing Fabric prerequisites (this may take a few minutes)..."
        cd "$FABRIC_X_DIR"
        ./install-fabric.sh --fabric-version 3.1.1
        print_ok "Fabric prerequisites installed"
    fi

    # Step 3: Generate crypto material
    print_step "3/5" "Checking crypto material..."
    if [ -d "$FABRIC_X_DIR/crypto" ]; then
        print_ok "Crypto material already exists, skipping"
    else
        echo "  Generating crypto material..."
        cd "$FABRIC_X_DIR"
        go tool cryptogen generate \
            --config crypto-config.yaml \
            --output crypto
        go tool configtxgen \
            --channelID mychannel \
            --profile OrgsChannel \
            --outputBlock crypto/sc-genesis-block.proto.bin
        CRYPTO_DIR=crypto ./scripts/cp_fabricx.sh
        print_ok "Crypto material generated"
    fi

    # Step 4: Build FSC node images
    print_step "4/5" "Checking FSC node images..."
    if docker images | grep tokens-endorser1 > /dev/null 2>&1; then
        print_ok "FSC images already built, skipping"
    else
        echo "  Building FSC node images (this may take several minutes)..."
        cd "$FABRIC_X_DIR"
        PLATFORM=fabricx docker compose \
            -f compose.yml -f compose-endorser2.yml build
        print_ok "FSC node images built"
    fi

    # Step 5: Generate FSC keys
    print_step "5/5" "Checking FSC node keys..."
    if [ -d "$FABRIC_X_DIR/conf/endorser1/fsc" ]; then
        print_ok "FSC keys already exist, skipping"
    else
        echo "  Generating FSC node keys (starting CA, enrolling identities)..."
        cd "$FABRIC_X_DIR"
        ./scripts/gen_crypto.sh
        print_ok "FSC node keys generated"
    fi

    echo ""
    echo -e "${GREEN}${BOLD}Setup complete.${NC}"
    echo -e "Run ${CYAN}./fablo-fabricx.sh up${NC} to start the network."
}

# ============================================================
# UP Command
# ============================================================

cmd_up() {
    print_banner "Fablo-FabricX: Starting Network"

    # Step 1: Generate configs
    print_step "1/12" "Generating Fabric-X configurations..."
    cd "$POC_DIR"
    if ! npm run generate --silent; then
        print_fail "Config generation failed"
        exit 1
    fi
    print_ok "Configurations generated"

    # Step 2: Validate setup exists
    print_step "2/12" "Validating setup..."
    local setup_ok=1
    [ -d "$FABRIC_X_DIR/crypto" ] || { print_fail "Crypto material missing"; setup_ok=0; }
    [ -d "$FABRIC_X_DIR/conf/endorser1/fsc" ] || { print_fail "FSC keys missing"; setup_ok=0; }
    docker images | grep tokens-endorser1 > /dev/null 2>&1 || { print_fail "FSC images not built"; setup_ok=0; }
    if [ $setup_ok -eq 0 ]; then
        echo -e "${RED}Setup not complete. Run './fablo-fabricx.sh setup' first.${NC}"
        exit 1
    fi
    print_ok "Setup validated"

    # Step 3: Clean previous FSC state
    print_step "3/12" "Cleaning previous FSC state..."
    clean_fsc_data
    print_ok "Previous state cleaned"

    # Step 4: Backup original configs
    print_step "4/12" "Backing up original configs..."
    for node in $NODES; do
        cp "$FABRIC_X_DIR/conf/$node/core.yaml" \
           "$FABRIC_X_DIR/conf/$node/core.yaml.bak"
        cp "$FABRIC_X_DIR/conf/$node/routing-config.yaml" \
           "$FABRIC_X_DIR/conf/$node/routing-config.yaml.bak"
    done
    print_ok "Node configs backed up"

    # Step 5: Deploy generated configs
    print_step "5/12" "Deploying generated configs..."
    for node in $NODES; do
        cp "$POC_DIR/generated-output/conf/$node/core.yaml" \
           "$FABRIC_X_DIR/conf/$node/core.yaml"
        cp "$POC_DIR/generated-output/conf/$node/routing-config.yaml" \
           "$FABRIC_X_DIR/conf/$node/routing-config.yaml"
    done
    print_ok "Node configs deployed"

    # Step 6: Deploy generated docker-compose
    print_step "6/12" "Deploying generated docker-compose..."
    cp "$FABRIC_X_DIR/compose.yml" "$FABRIC_X_DIR/compose.yml.bak"
    cp "$POC_DIR/generated-output/docker-compose.yml" \
       "$FABRIC_X_DIR/compose.yml"
    print_ok "compose.yml replaced with generated version (original backed up)"

    # Step 7: Create Docker network
    print_step "7/12" "Creating Docker network..."
    docker network create fabric_test 2>/dev/null || true
    print_ok "Docker network ready"

    # Step 8: Start the network
    print_step "8/12" "Starting Fabric-X network (committer + FSC nodes)..."
    cd "$FABRIC_X_DIR"
    docker compose up -d --wait
    print_ok "All containers started"

    # Step 9: Create namespace
    print_step "9/12" "Creating token namespace..."
    sleep 5
    cd "$FABRIC_X_DIR"
    go tool fxconfig namespace create token_namespace \
        --channel=mychannel \
        --orderer=localhost:7050 \
        --mspID=Org1MSP \
        --mspConfigPath=crypto/peerOrganizations/org1.example.com/users/channel_admin@org1.example.com/msp \
        --pk=crypto/peerOrganizations/org1.example.com/users/endorser@org1.example.com/msp/signcerts/endorser@org1.example.com-cert.pem
    print_ok "Namespace 'token_namespace' created"

    # Step 10: Wait for FSC nodes to be ready
    print_step "10/12" "Waiting for FSC nodes..."
    sleep 15
    for port in 9100 9300 9400 9500 9600; do
        curl -sf http://localhost:$port/healthz > /dev/null || {
            print_warn "Node on port $port not healthy yet"
        }
    done
    print_ok "FSC node health check complete"

    # Step 11: Initialize endorser
    print_step "11/12" "Initializing endorser..."
    curl -s -X POST http://localhost:9300/endorser/init > /dev/null 2>&1 || true
    sleep 3
    print_ok "Endorser initialized"

    # Step 12: Report
    print_step "12/12" "Network status..."
    echo ""
    echo -e "${GREEN}${BOLD}=========================================${NC}"
    echo -e "${GREEN}${BOLD}  Fabric-X network is UP${NC}"
    echo -e "${GREEN}${BOLD}=========================================${NC}"
    echo ""
    docker ps --format "table {{.Names}}\t{{.Status}}"
    echo ""
    echo -e "  ${BOLD}API Endpoints:${NC}"
    echo -e "    Issuer:    ${CYAN}http://localhost:9100${NC}"
    echo -e "    Endorser1: ${CYAN}http://localhost:9300${NC}"
    echo -e "    Endorser2: ${CYAN}http://localhost:9400${NC}"
    echo -e "    Owner1:    ${CYAN}http://localhost:9500${NC}"
    echo -e "    Owner2:    ${CYAN}http://localhost:9600${NC}"
}

# ============================================================
# DOWN Command
# ============================================================

cmd_down() {
    print_banner "Fablo-FabricX: Tearing Down Network"

    # Step 1: Stop all containers
    print_step "1/5" "Stopping containers..."
    cd "$FABRIC_X_DIR"
    docker compose down -v 2>/dev/null || true
    # Also try the old compose files in case they were used
    docker compose -f compose-xdev.yml down -v 2>/dev/null || true
    print_ok "Containers stopped"

    # Step 2: Remove Docker network
    print_step "2/5" "Removing Docker network..."
    docker network rm fabric_test 2>/dev/null || true
    print_ok "Network removed"

    # Step 3: Clean FSC state
    print_step "3/5" "Cleaning FSC node state..."
    clean_fsc_data
    print_ok "FSC state cleaned"

    # Step 4: Restore backed up configs
    print_step "4/5" "Restoring original configurations..."
    restore_backups
    print_ok "Original configs restored"

    # Step 5: Report
    print_step "5/5" "Done."
    echo ""
    echo -e "${GREEN}Fabric-X network is DOWN. All state cleaned.${NC}"
}

# ============================================================
# TEST Command
# ============================================================

cmd_test() {
    print_banner "Fabric-X Token Lifecycle E2E Test"

    local passed=0
    local failed=0

    # Pre-check: is the network running?
    if ! curl -sf http://localhost:9100/healthz > /dev/null 2>&1; then
        print_fail "Network not running. Run './fablo-fabricx.sh up' first."
        exit 1
    fi

    # 1. Health check all 5 FSC nodes
    echo -e "${BOLD}--- Health Checks ---${NC}"
    local health_ok=1
    check_health 9100 "issuer" || health_ok=0
    check_health 9300 "endorser1" || health_ok=0
    check_health 9400 "endorser2" || health_ok=0
    check_health 9500 "owner1" || health_ok=0
    check_health 9600 "owner2" || health_ok=0
    if [ $health_ok -eq 0 ]; then
        print_fail "Not all nodes healthy — aborting test"
        exit 1
    fi
    echo ""

    # 2. Issue 100 EURX to alice (owner1)
    echo -e "${BOLD}--- Issue 100 EURX to alice (owner1) ---${NC}"
    resp=$(curl -s -X POST http://localhost:9100/issuer/issue \
        -H "Content-Type: application/json" \
        -d '{"amount":{"code":"EURX","value":100},"counterparty":{"node":"owner1","account":"alice"}}')
    echo "  Response: $resp"
    if echo "$resp" | grep -q '"ok"'; then
        print_ok "Issued 100 EURX to alice"
        passed=$((passed + 1))
    else
        print_fail "Issue to alice failed"
        failed=$((failed + 1))
    fi
    sleep 5

    # 3. Issue 50 EURX to carlos (owner2)
    echo -e "${BOLD}--- Issue 50 EURX to carlos (owner2) ---${NC}"
    resp=$(curl -s -X POST http://localhost:9100/issuer/issue \
        -H "Content-Type: application/json" \
        -d '{"amount":{"code":"EURX","value":50},"counterparty":{"node":"owner2","account":"carlos"}}')
    echo "  Response: $resp"
    if echo "$resp" | grep -q '"ok"'; then
        print_ok "Issued 50 EURX to carlos"
        passed=$((passed + 1))
    else
        print_fail "Issue to carlos failed"
        failed=$((failed + 1))
    fi
    sleep 5

    # 4. Check alice balance = 100
    echo -e "${BOLD}--- Check balances after issuance ---${NC}"
    alice_bal=$(curl -s http://localhost:9500/owner/accounts/alice)
    echo "  Alice balance: $alice_bal"
    if echo "$alice_bal" | grep -q '"100"'; then
        print_ok "Alice balance = 100"
        passed=$((passed + 1))
    else
        print_warn "Alice balance check — expected 100, got: $alice_bal"
        failed=$((failed + 1))
    fi

    # 5. Check carlos balance = 50
    carlos_bal=$(curl -s http://localhost:9600/owner/accounts/carlos)
    echo "  Carlos balance: $carlos_bal"
    if echo "$carlos_bal" | grep -q '"50"'; then
        print_ok "Carlos balance = 50"
        passed=$((passed + 1))
    else
        print_warn "Carlos balance check — expected 50, got: $carlos_bal"
        failed=$((failed + 1))
    fi
    echo ""

    # 6. Transfer 30 EURX from alice to carlos
    echo -e "${BOLD}--- Transfer 30 EURX: alice → carlos ---${NC}"
    resp=$(curl -s -X POST http://localhost:9500/owner/accounts/alice/transfer \
        -H "Content-Type: application/json" \
        -d '{"amount":{"code":"EURX","value":30},"counterparty":{"node":"owner2","account":"carlos"}}')
    echo "  Response: $resp"
    if echo "$resp" | grep -q '"ok"'; then
        print_ok "Transferred 30 EURX from alice to carlos"
        passed=$((passed + 1))
    else
        print_fail "Transfer failed"
        failed=$((failed + 1))
    fi
    sleep 5

    # 7. Check alice balance = 70
    echo -e "${BOLD}--- Final balances ---${NC}"
    alice_final=$(curl -s http://localhost:9500/owner/accounts/alice)
    echo "  Alice final: $alice_final"
    if echo "$alice_final" | grep -q '"70"'; then
        print_ok "Alice balance = 70"
        passed=$((passed + 1))
    else
        print_warn "Alice final balance — expected 70, got: $alice_final"
        failed=$((failed + 1))
    fi

    # 8. Check carlos balance = 80
    carlos_final=$(curl -s http://localhost:9600/owner/accounts/carlos)
    echo "  Carlos final: $carlos_final"
    if echo "$carlos_final" | grep -q '"80"'; then
        print_ok "Carlos balance = 80"
        passed=$((passed + 1))
    else
        print_warn "Carlos final balance — expected 80, got: $carlos_final"
        failed=$((failed + 1))
    fi
    echo ""

    # 9. Print PASS/FAIL summary
    echo -e "${BOLD}========================================${NC}"
    if [ $failed -eq 0 ]; then
        echo -e "${GREEN}${BOLD}  ALL TESTS PASSED ✅  ($passed/$((passed + failed)))${NC}"
    else
        echo -e "${RED}${BOLD}  TESTS FAILED ❌  (passed=$passed, failed=$failed)${NC}"
    fi
    echo -e "${BOLD}========================================${NC}"

    [ $failed -ne 0 ] && exit 1
    return 0
}

# ============================================================
# STATUS Command
# ============================================================

cmd_status() {
    print_banner "Fablo-FabricX: Network Status"

    echo -e "${BOLD}--- Containers ---${NC}"
    docker ps --filter network=fabric_test \
        --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null \
        || echo "  No containers found"
    echo ""

    echo -e "${BOLD}--- FSC Node Health ---${NC}"
    check_health 9100 "issuer" || true
    check_health 9300 "endorser1" || true
    check_health 9400 "endorser2" || true
    check_health 9500 "owner1" || true
    check_health 9600 "owner2" || true
    echo ""

    echo -e "${BOLD}--- Port Mappings ---${NC}"
    echo "  Committer:  4001 (sidecar), 7050 (orderer), 7001 (query), 5433 (db)"
    echo "  Issuer:     9100 → 9000"
    echo "  Endorser1:  9300 → 9000"
    echo "  Endorser2:  9400 → 9000"
    echo "  Owner1:     9500 → 9000"
    echo "  Owner2:     9600 → 9000"
}

# ============================================================
# GENERATE Command
# ============================================================

cmd_generate() {
    print_banner "Fablo-FabricX: Generate Configs"

    cd "$POC_DIR"
    if ! npm run generate --silent; then
        print_fail "Config generation failed"
        exit 1
    fi

    echo ""
    echo -e "${BOLD}Generated files:${NC}"
    find "$GENERATED_DIR" -type f | sort | sed "s|^$POC_DIR/||" | while read -r f; do
        echo "  $f"
    done
    echo ""
    print_ok "Configuration generated (not deployed)"
    echo -e "  Run ${CYAN}./fablo-fabricx.sh up${NC} to deploy and start the network."
}

# ============================================================
# Command Router
# ============================================================

case "$COMMAND" in
    setup)    cmd_setup ;;
    up)       cmd_up ;;
    down)     cmd_down ;;
    test)     cmd_test ;;
    status)   cmd_status ;;
    generate) cmd_generate ;;
    *)
        echo "Usage: ./fablo-fabricx.sh {setup|up|down|test|status|generate}"
        echo ""
        echo "  setup    — One-time: install prereqs, generate crypto, build images"
        echo "  up       — Generate configs, deploy, and start the network"
        echo "  down     — Stop network, restore configs, clean state"
        echo "  test     — Run token lifecycle E2E test"
        echo "  status   — Show container and health status"
        echo "  generate — Generate configs only (no deploy)"
        exit 1
        ;;
esac
