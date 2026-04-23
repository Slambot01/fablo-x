#!/usr/bin/env bash
set -e

# ============================================================
# Fablo-X Lifecycle Manager
# Orchestrates the full Fabric-X token network bootstrap using
# generated configurations from the Fablo-X generator.
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

die() {
    print_fail "$1"
    exit 1
}

get_port() {
    case "$1" in
        issuer)    echo 9100 ;;
        endorser1) echo 9300 ;;
        endorser2) echo 9400 ;;
        owner1)    echo 9500 ;;
        owner2)    echo 9600 ;;
        *)         echo 0 ;;
    esac
}

# Back up a file only if a .bak does not already exist.
# Prevents overwriting a previous backup.
backup_file() {
    local file="$1"
    if [ -f "$file" ] && [ ! -f "$file.bak" ]; then
        cp "$file" "$file.bak"
    elif [ -f "$file.bak" ]; then
        print_warn "Backup exists: $(basename "$file").bak (kept)"
    fi
}

# Restore all original files from .bak and remove the .bak copies.
restore_backups() {
    local restored=0
    for node in $NODES; do
        for cfg in core.yaml routing-config.yaml; do
            local bak="$FABRIC_X_DIR/conf/$node/$cfg.bak"
            if [ -f "$bak" ]; then
                mv "$bak" "$FABRIC_X_DIR/conf/$node/$cfg"
                restored=$((restored + 1))
            fi
        done
    done
    for cfile in compose.yml compose-xdev.yml compose-endorser2.yml; do
        local bak="$FABRIC_X_DIR/$cfile.bak"
        if [ -f "$bak" ]; then
            mv "$bak" "$FABRIC_X_DIR/$cfile"
            restored=$((restored + 1))
        fi
    done
    if [ $restored -gt 0 ]; then
        print_ok "Restored $restored original file(s)"
    else
        print_warn "No backup files found to restore"
    fi
}

# Clean FSC node data directories.
# Data dirs are created by Docker (root-owned), so use a container to clean.
clean_fsc_data() {
    for node in $NODES; do
        local datadir="$FABRIC_X_DIR/conf/$node/data"
        if [ -d "$datadir" ]; then
            docker run --rm -v "$datadir:/data" \
                alpine sh -c "rm -rf /data/*" 2>/dev/null || true
            rm -rf "$datadir" 2>/dev/null || true
        fi
    done
}

# Check health of a single FSC node by name.
check_health() {
    local name="$1"
    local port
    port=$(get_port "$name")
    if curl -sf "http://localhost:$port/healthz" > /dev/null 2>&1; then
        print_ok "$name (port $port): HEALTHY"
        return 0
    else
        print_fail "$name (port $port): UNHEALTHY"
        return 1
    fi
}

# Poll all FSC nodes until healthy or timeout.
# Usage: wait_for_nodes [max_seconds]
wait_for_nodes() {
    local max_wait=${1:-120}
    local interval=3
    local elapsed=0
    local all_healthy

    echo "  Waiting up to ${max_wait}s for all FSC nodes..."
    while [ $elapsed -lt $max_wait ]; do
        all_healthy=1
        for node in $NODES; do
            local port
            port=$(get_port "$node")
            if ! curl -sf "http://localhost:$port/healthz" > /dev/null 2>&1; then
                all_healthy=0
                break
            fi
        done
        if [ $all_healthy -eq 1 ]; then
            print_ok "All FSC nodes healthy (after ${elapsed}s)"
            return 0
        fi
        sleep $interval
        elapsed=$((elapsed + interval))
    done

    # Report individual status on timeout
    print_warn "Timed out after ${max_wait}s — individual status:"
    for node in $NODES; do
        check_health "$node" || true
    done
    return 1
}

# -- Safety trap: restore configs on interrupt --
trap 'echo ""; print_warn "Interrupted — restoring original configs..."; restore_backups; exit 130' INT TERM

# ============================================================
# Validate FABRIC_X_DIR exists
# ============================================================

if [ ! -d "$FABRIC_X_DIR" ]; then
    die "Fabric-X directory not found: $FABRIC_X_DIR"
fi

COMMAND="${1:-help}"

# ============================================================
# SETUP Command
# ============================================================

cmd_setup() {
    print_banner "Fablo-X: One-Time Setup"

    # Step 1: Validate environment
    print_step "1/5" "Validating environment..."
    local missing=0
    for cmd in docker go make npm; do
        if ! command -v "$cmd" > /dev/null 2>&1; then
            print_fail "$cmd is not installed"
            missing=1
        fi
    done
    if ! docker compose version > /dev/null 2>&1; then
        print_fail "docker compose plugin is not available"
        missing=1
    fi
    if ! docker info > /dev/null 2>&1; then
        print_fail "Docker daemon is not running"
        missing=1
    fi
    [ $missing -eq 1 ] && die "Fix missing dependencies and retry."
    print_ok "All dependencies available (docker, docker compose, go, make, npm)"

    # Step 2: Install Fabric prerequisites
    print_step "2/5" "Checking Fabric prerequisites..."
    if [ -d "$FABRIC_X_DIR/fabric-samples/bin" ]; then
        print_ok "Prerequisites already installed (skipped)"
    else
        echo "  Installing Fabric prerequisites (this may take several minutes)..."
        cd "$FABRIC_X_DIR"
        make install-prerequisites
        print_ok "Fabric prerequisites installed"
    fi

    # Step 3: Generate crypto material
    print_step "3/5" "Checking crypto material..."
    if [ -d "$FABRIC_X_DIR/crypto" ]; then
        print_ok "Crypto material exists (skipped)"
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
    if docker images --format '{{.Repository}}' | grep -q "tokens-issuer"; then
        print_ok "FSC images already built (skipped)"
    else
        echo "  Building FSC node images (this may take several minutes)..."
        cd "$FABRIC_X_DIR"
        PLATFORM=fabricx docker compose \
            -f compose.yml -f compose-endorser2.yml build
        print_ok "FSC node images built"
    fi

    # Step 5: Generate FSC keys
    print_step "5/5" "Checking FSC node keys..."
    if [ -d "$FABRIC_X_DIR/conf/issuer/keys" ]; then
        print_ok "FSC keys already exist (skipped)"
    else
        echo "  Generating FSC node keys (starting CA, enrolling identities)..."
        cd "$FABRIC_X_DIR"
        ./scripts/gen_crypto.sh
        print_ok "FSC node keys generated"
    fi

    echo ""
    echo -e "${GREEN}${BOLD}Setup complete.${NC}"
    echo -e "Run ${CYAN}./fablo-x.sh up${NC} to start the network."
}

# ============================================================
# UP Command
# ============================================================

cmd_up() {
    print_banner "Fablo-X: Starting Network"

    # Step 1: Generate configs
    print_step "1/13" "Generating Fabric-X configurations..."
    cd "$POC_DIR"
    if ! npm run generate --silent; then
        die "Config generation failed"
    fi
    print_ok "Configurations generated"

    # Step 2: Validate setup has been run
    print_step "2/13" "Validating setup..."
    local setup_ok=1
    [ -d "$FABRIC_X_DIR/crypto" ] || { print_fail "Crypto material missing"; setup_ok=0; }
    [ -d "$FABRIC_X_DIR/conf/issuer/keys" ] || { print_fail "FSC keys missing"; setup_ok=0; }
    if ! docker images --format '{{.Repository}}' | grep -q "tokens-issuer"; then
        print_fail "FSC images not built"
        setup_ok=0
    fi
    [ $setup_ok -eq 0 ] && die "Setup incomplete. Run './fablo-x.sh setup' first."
    print_ok "Setup validated"

    # Step 3: Stop any previous containers
    print_step "3/13" "Stopping any previous containers..."
    cd "$FABRIC_X_DIR"
    docker compose -f compose.yml down -v 2>/dev/null || true
    docker compose -f compose-xdev.yml down -v 2>/dev/null || true
    docker compose -f compose-endorser2.yml down -v 2>/dev/null || true
    docker network rm fabric_test 2>/dev/null || true
    print_ok "Previous containers stopped"

    # Step 4: Clean FSC state
    print_step "4/13" "Cleaning previous FSC state..."
    clean_fsc_data
    print_ok "Previous state cleaned"

    # Step 5: Backup original configs (only if .bak doesn't exist)
    print_step "5/13" "Backing up original configs..."
    for node in $NODES; do
        backup_file "$FABRIC_X_DIR/conf/$node/core.yaml"
        backup_file "$FABRIC_X_DIR/conf/$node/routing-config.yaml"
    done
    backup_file "$FABRIC_X_DIR/compose.yml"
    backup_file "$FABRIC_X_DIR/compose-xdev.yml"
    backup_file "$FABRIC_X_DIR/compose-endorser2.yml"
    print_ok "Original configs backed up"

    # Step 6: Deploy generated node configs
    print_step "6/13" "Deploying generated node configs..."
    for node in $NODES; do
        cp "$GENERATED_DIR/conf/$node/core.yaml" \
           "$FABRIC_X_DIR/conf/$node/core.yaml"
        cp "$GENERATED_DIR/conf/$node/routing-config.yaml" \
           "$FABRIC_X_DIR/conf/$node/routing-config.yaml"
    done
    print_ok "Node configs deployed (5 nodes × 2 files)"

    # Step 7: Deploy generated docker-compose
    print_step "7/13" "Deploying generated docker-compose..."
    cp "$GENERATED_DIR/docker-compose.yml" "$FABRIC_X_DIR/compose.yml"
    print_ok "compose.yml replaced with generated version"

    # Step 8: Create Docker network
    print_step "8/13" "Creating Docker network..."
    docker network create fabric_test 2>/dev/null || true
    print_ok "Docker network 'fabric_test' ready"

    # Step 9: Start the network
    print_step "9/13" "Starting Fabric-X network (committer + FSC nodes)..."
    cd "$FABRIC_X_DIR"
    docker compose -f compose.yml up -d --wait
    print_ok "All containers started"

    # Step 10: Create namespace
    print_step "10/13" "Creating token namespace..."
    sleep 5
    cd "$FABRIC_X_DIR"
    go tool fxconfig namespace create token_namespace \
        --channel=mychannel \
        --orderer=localhost:7050 \
        --mspID=Org1MSP \
        --mspConfigPath=crypto/peerOrganizations/org1.example.com/users/channel_admin@org1.example.com/msp \
        --pk=crypto/peerOrganizations/org1.example.com/users/endorser@org1.example.com/msp/signcerts/endorser@org1.example.com-cert.pem
    print_ok "Namespace 'token_namespace' created"

    # Step 11: Wait for FSC nodes to be healthy
    print_step "11/13" "Waiting for FSC nodes to be healthy..."
    if ! wait_for_nodes 120; then
        print_warn "Some nodes not healthy — continuing anyway"
    fi

    # Step 12: Initialize endorser
    print_step "12/13" "Initializing endorser..."
    if curl -sf -X POST http://localhost:9300/endorser/init > /dev/null 2>&1; then
        print_ok "Endorser initialized"
    else
        print_warn "Endorser init returned non-zero (may need manual init)"
    fi
    sleep 3

    # Step 13: Report
    print_step "13/13" "Network status"
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
    print_banner "Fablo-X: Tearing Down Network"

    # Step 1: Stop containers (try both generated and original compose files)
    print_step "1/5" "Stopping containers..."
    cd "$FABRIC_X_DIR"
    docker compose -f compose.yml down -v 2>/dev/null || true
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

    # Step 4: Restore original configs from backups
    print_step "4/5" "Restoring original configurations..."
    restore_backups

    # Step 5: Done
    print_step "5/5" "Done"
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
        die "Network not running. Run './fablo-x.sh up' first."
    fi

    # 1. Health check all 5 FSC nodes
    echo -e "${BOLD}--- Health Checks ---${NC}"
    local health_ok=1
    for node in $NODES; do
        check_health "$node" || health_ok=0
    done
    if [ $health_ok -eq 0 ]; then
        die "Not all nodes healthy — aborting test"
    fi
    echo ""

    # 2. Issue 100 EURX to alice (owner1)
    echo -e "${BOLD}--- Issue 100 EURX to alice (owner1) ---${NC}"
    local resp
    resp=$(curl -sf -X POST http://localhost:9100/issuer/issue \
        -H "Content-Type: application/json" \
        -d '{"amount":{"code":"EURX","value":100},"counterparty":{"node":"owner1","account":"alice"}}') \
        || resp="ERROR"
    echo "  Response: $resp"
    if [ "$resp" != "ERROR" ]; then
        print_ok "PASS: Issued 100 EURX to alice"
        passed=$((passed + 1))
    else
        print_fail "FAIL: Issue to alice"
        failed=$((failed + 1))
    fi
    sleep 5

    # 3. Issue 50 EURX to carlos (owner2)
    echo -e "${BOLD}--- Issue 50 EURX to carlos (owner2) ---${NC}"
    resp=$(curl -sf -X POST http://localhost:9100/issuer/issue \
        -H "Content-Type: application/json" \
        -d '{"amount":{"code":"EURX","value":50},"counterparty":{"node":"owner2","account":"carlos"}}') \
        || resp="ERROR"
    echo "  Response: $resp"
    if [ "$resp" != "ERROR" ]; then
        print_ok "PASS: Issued 50 EURX to carlos"
        passed=$((passed + 1))
    else
        print_fail "FAIL: Issue to carlos"
        failed=$((failed + 1))
    fi
    sleep 5

    # 4. Check alice balance = 100
    echo -e "${BOLD}--- Check balances after issuance ---${NC}"
    local alice_bal
    alice_bal=$(curl -sf http://localhost:9500/owner/accounts/alice) || alice_bal="ERROR"
    echo "  Alice raw: $alice_bal"
    if echo "$alice_bal" | grep -q '100'; then
        print_ok "PASS: Alice balance = 100"
        passed=$((passed + 1))
    else
        print_fail "FAIL: Alice balance — expected 100, got: $alice_bal"
        failed=$((failed + 1))
    fi

    # 5. Check carlos balance = 50
    local carlos_bal
    carlos_bal=$(curl -sf http://localhost:9600/owner/accounts/carlos) || carlos_bal="ERROR"
    echo "  Carlos raw: $carlos_bal"
    if echo "$carlos_bal" | grep -q '50'; then
        print_ok "PASS: Carlos balance = 50"
        passed=$((passed + 1))
    else
        print_fail "FAIL: Carlos balance — expected 50, got: $carlos_bal"
        failed=$((failed + 1))
    fi
    echo ""

    # 6. Transfer 30 EURX from alice to carlos
    echo -e "${BOLD}--- Transfer 30 EURX: alice → carlos ---${NC}"
    resp=$(curl -sf -X POST http://localhost:9500/owner/accounts/alice/transfer \
        -H "Content-Type: application/json" \
        -d '{"amount":{"code":"EURX","value":30},"counterparty":{"node":"owner2","account":"carlos"}}') \
        || resp="ERROR"
    echo "  Response: $resp"
    if [ "$resp" != "ERROR" ]; then
        print_ok "PASS: Transferred 30 EURX alice → carlos"
        passed=$((passed + 1))
    else
        print_fail "FAIL: Transfer"
        failed=$((failed + 1))
    fi
    sleep 5

    # 7. Check alice balance = 70
    echo -e "${BOLD}--- Final balances ---${NC}"
    local alice_final
    alice_final=$(curl -sf http://localhost:9500/owner/accounts/alice) || alice_final="ERROR"
    echo "  Alice final: $alice_final"
    if echo "$alice_final" | grep -q '70'; then
        print_ok "PASS: Alice balance = 70"
        passed=$((passed + 1))
    else
        print_fail "FAIL: Alice final — expected 70, got: $alice_final"
        failed=$((failed + 1))
    fi

    # 8. Check carlos balance = 80
    local carlos_final
    carlos_final=$(curl -sf http://localhost:9600/owner/accounts/carlos) || carlos_final="ERROR"
    echo "  Carlos final: $carlos_final"
    if echo "$carlos_final" | grep -q '80'; then
        print_ok "PASS: Carlos balance = 80"
        passed=$((passed + 1))
    else
        print_fail "FAIL: Carlos final — expected 80, got: $carlos_final"
        failed=$((failed + 1))
    fi
    echo ""

    # Summary
    local total=$((passed + failed))
    echo -e "${BOLD}========================================${NC}"
    if [ $failed -eq 0 ]; then
        echo -e "${GREEN}${BOLD}  ALL TESTS PASSED ✅  ($passed/$total)${NC}"
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
    print_banner "Fablo-X: Network Status"

    echo -e "${BOLD}--- Containers ---${NC}"
    docker ps --filter network=fabric_test \
        --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null \
        || echo "  No containers found"
    echo ""

    echo -e "${BOLD}--- FSC Node Health ---${NC}"
    for node in $NODES; do
        check_health "$node" || true
    done
    echo ""

    echo -e "${BOLD}--- Port Mappings ---${NC}"
    echo "  Committer:  4001 (sidecar), 7050 (orderer), 7001 (query), 5433 (db)"
    echo "  Issuer:     localhost:9100 → container:9000"
    echo "  Endorser1:  localhost:9300 → container:9000"
    echo "  Endorser2:  localhost:9400 → container:9000"
    echo "  Owner1:     localhost:9500 → container:9000"
    echo "  Owner2:     localhost:9600 → container:9000"
}

# ============================================================
# GENERATE Command
# ============================================================

cmd_generate() {
    print_banner "Fablo-X: Generate Configs"

    cd "$POC_DIR"
    if ! npm run generate --silent; then
        die "Config generation failed"
    fi

    echo ""
    echo -e "${BOLD}Generated files:${NC}"
    find "$GENERATED_DIR" -type f | sort | sed "s|^$POC_DIR/||" | while read -r f; do
        echo "  $f"
    done
    echo ""
    print_ok "Configuration generated (not deployed)"
    echo -e "  Run ${CYAN}./fablo-x.sh up${NC} to deploy and start the network."
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
        echo -e "${BOLD}Fablo-X Lifecycle Manager${NC}"
        echo ""
        echo "Usage: ./fablo-x.sh {setup|up|down|test|status|generate}"
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
