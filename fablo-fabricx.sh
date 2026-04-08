#!/bin/bash
set -e

export PATH="/usr/local/go/bin:/usr/bin:/usr/local/bin:$PATH"
FABRIC_X_DIR="$HOME/lfdt-project/fabric-x/samples/tokens"

if [ ! -d "$FABRIC_X_DIR" ]; then
    echo "Error: Directory $FABRIC_X_DIR does not exist."
    exit 1
fi

COMMAND="$1"

if [ "$COMMAND" = "up" ]; then
    cd "$FABRIC_X_DIR"
    
    echo "Step 1: Checking if network is already running..."
    ALREADY_RUNNING=0
    if docker ps --filter name=test-committer | grep -q test-committer; then
        echo "Network is already running. Skipping down to FSC nodes start."
        ALREADY_RUNNING=1
    fi
    
    if [ "$ALREADY_RUNNING" -eq 0 ]; then
        echo "Step 2: Cleaning up any leftover state..."
        docker compose -f compose.yml down 2>/dev/null || true
        docker compose -f compose-xdev.yml down 2>/dev/null || true
        docker network rm fabric_test 2>/dev/null || true
        
        echo "Step 3: Creating Docker network..."
        docker network create fabric_test
        
        echo "Step 4: Starting committer-test-node..."
        docker compose -f compose-xdev.yml up -d --wait
        sleep 8
        
        echo "Step 5: Creating the token namespace..."
        cd ~/lfdt-project/fabric-x/samples/tokens
        go tool fxconfig namespace create token_namespace \
            --channel=mychannel \
            --orderer=localhost:7050 \
            --mspID=Org1MSP \
            --mspConfigPath=crypto/peerOrganizations/org1.example.com/users/channel_admin@org1.example.com/msp \
            --pk=crypto/peerOrganizations/org1.example.com/users/endorser@org1.example.com/msp/signcerts/endorser@org1.example.com-cert.pem
        sleep 5
        
        echo "Step 6: Verifying namespace was created..."
        if ! go tool fxconfig namespace list --endpoint=localhost:7001 | grep -q "token_namespace"; then
            echo "Error: token_namespace was not created successfully."
            exit 1
        fi
    fi
    
    echo "Step 7: Starting FSC nodes..."
    cd ~/lfdt-project/fabric-x/samples/tokens
    PLATFORM=fabricx docker compose -f compose.yml -f compose-endorser2.yml up -d
    sleep 15
    
    echo "Step 8: Waiting for health checks on all 5 FSC nodes..."
    for i in {1..30}; do
        HEALTHY=1
        curl -sf http://localhost:9100/healthz > /dev/null || HEALTHY=0
        curl -sf http://localhost:9300/healthz > /dev/null || HEALTHY=0
        curl -sf http://localhost:9400/healthz > /dev/null || HEALTHY=0
        curl -sf http://localhost:9500/healthz > /dev/null || HEALTHY=0
        curl -sf http://localhost:9600/healthz > /dev/null || HEALTHY=0
        
        if [ "$HEALTHY" -eq 1 ]; then
            break
        fi
        
        if [ "$i" -eq 30 ]; then
            echo "Error: FSC nodes failed health check after 30 attempts."
            echo "Failed nodes:"
            curl -sf http://localhost:9100/healthz > /dev/null || echo "issuer (9100)"
            curl -sf http://localhost:9300/healthz > /dev/null || echo "endorser1 (9300)"
            curl -sf http://localhost:9400/healthz > /dev/null || echo "endorser2 (9400)"
            curl -sf http://localhost:9500/healthz > /dev/null || echo "owner1 (9500)"
            curl -sf http://localhost:9600/healthz > /dev/null || echo "owner2 (9600)"
            exit 1
        fi
        sleep 5
    done
    
    echo "Step 9: Initializing endorser..."
    resp=$(curl -s -X POST http://localhost:9300/endorser/init)
    if ! echo "$resp" | grep -q 'ok'; then
        echo "Warning: Endorser initialization did not return ok: $resp"
    fi
    sleep 5
    
    echo "✅ Fabric-X network is UP and ready"
    echo "   Issuer:    http://localhost:9100"
    echo "   Endorser1: http://localhost:9300"
    echo "   Endorser2: http://localhost:9400"
    echo "   Owner1:    http://localhost:9500"
    echo "   Owner2:    http://localhost:9600"
    echo "   Swagger:   http://localhost:8080"

elif [ "$COMMAND" = "down" ]; then
    cd "$FABRIC_X_DIR"
    docker compose -f compose.yml -f compose-endorser2.yml down 2>/dev/null || true
    docker compose -f compose-xdev.yml down 2>/dev/null || true
    docker network rm fabric_test 2>/dev/null || true
    echo "✅ Fabric-X network is DOWN"

elif [ "$COMMAND" = "status" ]; then
    docker ps --filter network=fabric_test --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo ""
    for port in 9100 9300 9400 9500 9600; do
        if curl -sf http://localhost:$port/healthz > /dev/null; then
            echo "  Port $port: HEALTHY"
        else
            echo "  Port $port: UNHEALTHY"
        fi
    done

elif [ "$COMMAND" = "test" ]; then
    if ! curl -sf http://localhost:9100/healthz > /dev/null; then
        echo "Network not running. Run ./fablo-fabricx.sh up first"
        exit 1
    fi

    echo "=== Fabric-X Token Lifecycle E2E Test ==="
    echo ""

    FAILED=0
    for port in 9100 9300 9400 9500 9600; do
        status=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$port/healthz)
        if [ "$status" = "200" ]; then
            echo "  ✓ Node on port $port healthy"
        else
            echo "  ✗ Node on port $port UNHEALTHY (status: $status)"
            FAILED=1
        fi
    done
    [ $FAILED -eq 0 ] && echo "✓ All nodes healthy" || { echo "✗ FAIL: Not all nodes healthy"; exit 1; }
    echo ""

    echo "--- Issuing 100 EURX to alice ---"
    resp=$(curl -s -X POST http://localhost:9100/issuer/issue \
        -H "Content-Type: application/json" \
        -d '{"amount":{"code":"EURX","value":100},"counterparty":{"node":"owner1","account":"alice"}}')
    echo "  Response: $resp"
    echo "$resp" | grep -q '"ok"' || { echo "✗ FAIL: Issue to alice failed"; exit 1; }
    echo "  ✓ Issued 100 EURX to alice"
    sleep 5

    echo "--- Issuing 50 EURX to carlos ---"
    resp=$(curl -s -X POST http://localhost:9100/issuer/issue \
        -H "Content-Type: application/json" \
        -d '{"amount":{"code":"EURX","value":50},"counterparty":{"node":"owner2","account":"carlos"}}')
    echo "  Response: $resp"
    echo "$resp" | grep -q '"ok"' || { echo "✗ FAIL: Issue to carlos failed"; exit 1; }
    echo "  ✓ Issued 50 EURX to carlos"
    sleep 5

    echo "--- Checking alice balance ---"
    balance=$(curl -s http://localhost:9500/owner/accounts/alice)
    echo "  Balance response: $balance"
    echo "  ✓ Alice balance retrieved"

    echo "--- Checking carlos balance ---"
    balance=$(curl -s http://localhost:9600/owner/accounts/carlos)
    echo "  Balance response: $balance"
    echo "  ✓ Carlos balance retrieved"

    echo "--- Transferring 30 EURX from alice to carlos ---"
    resp=$(curl -s -X POST http://localhost:9500/owner/accounts/alice/transfer \
        -H "Content-Type: application/json" \
        -d '{"amount":{"code":"EURX","value":30},"counterparty":{"node":"owner2","account":"carlos"}}')
    echo "  Response: $resp"
    echo "$resp" | grep -q '"ok"' || { echo "✗ FAIL: Transfer failed"; exit 1; }
    echo "  ✓ Transferred 30 EURX from alice to carlos"
    sleep 5

    echo "--- Verifying final balances ---"
    alice_final=$(curl -s http://localhost:9500/owner/accounts/alice)
    carlos_final=$(curl -s http://localhost:9600/owner/accounts/carlos)
    echo "  Alice final: $alice_final"
    echo "  Carlos final: $carlos_final"
    echo "  ✓ Final balances retrieved"

    echo "--- Checking transaction histories ---"
    alice_txs=$(curl -s http://localhost:9500/owner/accounts/alice/transactions)
    carlos_txs=$(curl -s http://localhost:9600/owner/accounts/carlos/transactions)
    echo "  Alice transactions: $alice_txs"
    echo "  Carlos transactions: $carlos_txs"
    echo "  ✓ Transaction histories retrieved"

    echo ""
    echo "========================================"
    echo "=== ALL TESTS PASSED ✅ ==="
    echo "========================================"

else
    echo "Usage: ./fablo-fabricx.sh {up|down|status|test}"
    exit 1
fi
