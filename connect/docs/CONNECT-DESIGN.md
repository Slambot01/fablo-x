# fablo connect — Technical Design Document

**Issue:** [#619](https://github.com/hyperledger-labs/fablo/issues/619)
**Status:** POC validated
**Date:** 2026-05-08

---

## 1. Overview

`fablo connect` is a proposed command that lets a peer from one Fablo network join a channel in another already-running Fablo network. The use case is cross-organization channel membership: Org2 wants to add a peer to a channel that Org1 already created and is running.

This POC implements the concept as a standalone shell script (`fablo-connect.sh`) driven by a JSON config file (`fablo-connect-config.json`). It was built to validate the minimum set of operations required and to surface every schema gap, TLS issue, and identity management problem that a production implementation would need to handle.

The POC is structured as two directories:

- **network1/** — a standard Fablo-generated network (1 org, 1 peer, 1 orderer, 1 CA, 1 channel). This represents the existing network that the new peer connects to.
- **network2/** — the connect implementation. Contains the config, templates, and scripts that enroll a new peer identity via the existing CA, start a peer container on the existing Docker network, and join it to the existing channel.

The lifecycle is:

```
fablo-connect.sh up      →  generate → enroll → start peer → join channel
fablo-connect.sh down    →  stop and remove peer container
fablo-connect.sh status  →  show peer status and channel membership
fablo-connect.sh test    →  verify peer joined the target channel
```

---

## 2. Schema Gap Analysis

The original proposal in Issue #619 described a connect config with 2 CA fields: `ca.url` and `ca.tlsCACertPath`. Building a working implementation required **7 fields total**. Five additional fields were discovered during implementation — each one surfaced as a runtime failure.

| Gap | Fields Required | Without These |
|-----|----------------|---------------|
| Orderer connectivity | `orderer.url` and `orderer.tlsCACertPath` | Genesis block fetch fails: `dial tcp: address null: missing port` |
| Docker network membership | `network.dockerNetworkName` | Docker error: `network null not found` |
| CA admin identity | `ca.adminMspPath` | Peer registration: MSP path undefined |
| CA credentials | `ca.adminUsername` and `ca.adminPassword` | Currently hardcoded as `admin:adminpw` via sed — not read from config |
| TLS hostname override | `orderer.hostnameOverride` | x509 validation fails — currently hardcoded as `orderer0.group1.org1.example.com` |

### Implementation vs. Schema

The current POC hardcodes several of these values rather than reading them from config:

- **`ca.adminMspPath`** is defined in `fablo-connect-config.json` (line 20) but **never read by any script**. Both `enroll-peer.sh` (line 36) and `join-channel.sh` (line 15) hardcode the equivalent absolute path directly.
- **`ca.adminUsername` / `ca.adminPassword`** are baked into a `sed` substitution in `enroll-peer.sh` line 13: `sed 's|https://|https://admin:adminpw@|'`. No config field exists for these values.
- **`orderer.hostnameOverride`** is hardcoded on `join-channel.sh` line 21: `--ordererTLSHostnameOverride orderer0.group1.org1.example.com`. No config field exists for this value.

These are gaps between the schema as defined and the schema as implemented.

---

## 3. Implementation Findings

### Finding 1: fabric-ca-client -M flag path resolution

`fabric-ca-client` requires the `-M` flag to specify the MSP output directory. Four different `-M` paths are used across the four enroll/register commands in `enroll-peer.sh`:

| Command | Line | -M / --mspdir path |
|---------|------|--------------------|
| Admin enroll | 16 | `-M $ADMIN_HOME/msp` |
| Peer register | 25 | `--mspdir $ADMIN_HOME/msp` |
| Peer enroll | 32 | `-M $FABRIC_CA_CLIENT_HOME/msp` |
| Peer TLS enroll | 45 | `-M $FABRIC_CA_CLIENT_HOME/tls-msp` |

The `FABRIC_CA_CLIENT_HOME` environment variable (set on line 8) also affects where `fabric-ca-client` writes its own `fabric-ca-client-config.yaml` — this is **separate** from the `-M` flag. Conflating these two concepts causes silent failures where the client config ends up in the wrong directory.

### Finding 2: Error Code 74 must be treated as success

**File:** `enroll-peer.sh`, line 25
```bash
--mspdir $ADMIN_HOME/msp || echo "Identity already registered"
```

When `fabric-ca-client register` returns exit code 74, it means the identity is already registered in the CA database. The `|| echo` pattern makes this non-fatal, which is required for idempotency — running `fablo-connect.sh up` twice must not fail.

However, this pattern catches **all** non-zero exits, not just code 74. An auth failure (wrong admin credentials) or a network timeout would also be silently swallowed. A correct implementation should check the specific exit code:

```bash
fabric-ca-client register ... ; rc=$?
if [ $rc -ne 0 ] && [ $rc -ne 74 ]; then
    echo "Registration failed with exit code $rc"; exit 1
fi
```

### Finding 3: NodeOUs not enabled — manual admincerts copy required

**File:** `enroll-peer.sh`, lines 34–36
```bash
# Enable admincerts since NodeOUs are not enabled
mkdir -p $FABRIC_CA_CLIENT_HOME/msp/admincerts
cp /home/ritesh/.../users/Admin@org1.example.com/msp/signcerts/Admin@org1.example.com-cert.pem \
   $FABRIC_CA_CLIENT_HOME/msp/admincerts/
```

Fablo-generated CAs do not enable NodeOUs by default. Without NodeOUs, the peer cannot determine which identities are admins by OU classification. It falls back to the legacy `admincerts/` folder, which is empty after a fresh CA enrollment.

The fix is to copy the network1 Admin's signing certificate into the peer's `msp/admincerts/` directory. The source path is currently hardcoded as an absolute path rather than being derived from `ca.adminMspPath` in the config (which exists in the JSON but is never read — see Finding 8).

### Finding 4: Orderer TLS hostname override is always required

**File:** `join-channel.sh`, line 21
```bash
--ordererTLSHostnameOverride orderer0.group1.org1.example.com
```

When connecting to the orderer via `localhost`, TLS validation fails because the orderer's certificate CN is `orderer0.group1.org1.example.com`, not `localhost`. The `--ordererTLSHostnameOverride` flag tells the TLS client to expect the orderer's actual hostname in the certificate instead of the connection address.

This value is hardcoded. It must match the orderer's certificate CN exactly. Fablo uses a composite naming convention (`orderer0.group1.org1.example.com` — note the `group1` segment) that differs from standard Fabric samples (`orderer.example.com`).

### Finding 5: Zero input validation

There are no `if [ -z ... ]` guards in any script. When a required field is missing from the config JSON, `jq -r` returns the literal string `null`, which is then passed to downstream commands. The resulting errors are cryptic:

| Missing field | Error |
|--------------|-------|
| `network.dockerNetworkName` | `network null not found` |
| `orgs[0].ca.url` | `connection refused` on port 80 |
| `orgs[0].ca.tlsCACertPath` | `open null: no such file or directory` |
| `orgs[0].orderer.url` | `dial tcp: address null: missing port` |
| `orgs[0].orderer.tlsCACertPath` | `open null: no such file or directory` |

A production implementation needs schema validation before any commands run, with specific error messages per missing field.

### Finding 6: Non-idempotent TLS key rename

**File:** `enroll-peer.sh`, lines 48–53
```bash
mv $FABRIC_CA_CLIENT_HOME/tls-msp/keystore/*_sk \
   $FABRIC_CA_CLIENT_HOME/tls-msp/server.key
mv $FABRIC_CA_CLIENT_HOME/tls-msp/signcerts/cert.pem \
   $FABRIC_CA_CLIENT_HOME/tls-msp/server.crt
mv $FABRIC_CA_CLIENT_HOME/tls-msp/tlscacerts/*.pem \
   $FABRIC_CA_CLIENT_HOME/tls-msp/ca.crt
```

These `mv` commands use glob patterns. On a second run — after a failed `down` that didn't clean `generated/crypto/` — the `*_sk` glob matches nothing because the file was already renamed to `server.key`. The `mv` fails, and `set -e` (line 2) aborts the script.

Register is idempotent (Finding 2), but the TLS rename step is not. The `down` command does not clean `generated/crypto/`, making this a practical problem in development.

### Finding 7: Docker network name is derived, not static

The network name `fablo_network_202605051022_basic` is constructed from:
1. Fablo's `COMPOSE_PROJECT_NAME` (in `.env`): `fablo_network_202605051022` — includes a timestamp
2. Docker Compose's default network suffix: `_basic` (from the network name in network1's `docker-compose.yaml`)

If network1 is re-generated (e.g., after `fablo recreate`), the timestamp changes and the connect config's `dockerNetworkName` becomes stale. A robust implementation would derive this name programmatically from the source network's `.env` file rather than requiring the user to manually copy it.

### Finding 8: ca.adminMspPath defined in config but never read

**File:** `fablo-connect-config.json`, line 20
```json
"adminMspPath": "/home/ritesh/.../users/Admin@org1.example.com/msp"
```

No script reads this field via `jq`. Both `enroll-peer.sh` (line 36, the admincerts copy) and `join-channel.sh` (line 15, the `CORE_PEER_MSPCONFIGPATH` export) hardcode the equivalent absolute path directly. This is a dead config field in the current implementation.

### Finding 9: fetch oldest vs fetch newest

**File:** `join-channel.sh`, line 17
```bash
peer channel fetch oldest \
  ./generated/my-channel1.block \
  -c my-channel1 \
  ...
```

Fablo's existing `channel_fns.sh` uses `fetch newest` in both `fetchChannelAndJoin()` (line 81) and `fetchChannelAndJoinTls()` (line 114). The connect POC intentionally uses `fetch oldest` because it retrieves the genesis block, which is the correct block type for a first-time channel join. This is a deliberate divergence from the existing pattern.

---

## 4. Verification

Channel membership was verified using the following docker exec command:

```bash
docker exec peer1.org1.example.com peer channel list
```

Output confirmed `my-channel1` in the channel list. The full automated test is in `fablo-connect.sh`'s `test_network()` function (lines 43–53):

```bash
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
```

The `status()` function (lines 37–41) provides a quick check:

```bash
docker exec peer1.org1.example.com peer channel list 2>/dev/null \
    || echo "cannot reach peer1"
```

---

## 5. What a Production Implementation Needs

Based on this POC, a production `fablo connect` command needs:

1. **Schema validation before any commands run**, with specific error messages per missing field — not cryptic `null` errors from downstream tools
2. **All 7 fields in the schema actually read from config** — not hardcoded. This includes `ca.adminMspPath` (currently dead), CA credentials (currently in a sed substitution), and `orderer.hostnameOverride` (currently a string literal)
3. **Idempotent `down`** that cleans `generated/crypto/` to prevent the TLS rename failure on re-run
4. **Specific exit code checking for fabric-ca-client** — trap code 74 only, not all non-zero exits
5. **Derived Docker network name** from the source network's `.env` file rather than a hardcoded timestamp-based name
6. **Parameterized peer identity** name and secret — not hardcoded as `peer1.org1.example.com` / `peer1pw`
