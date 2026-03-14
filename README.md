# NAS Remote Shutdown via Home Assistant + NUT UPS

Reliably shuts down a **Synology RS1221+** (DSM 7.3.2) when a **Unifi 2U UPS** (acting as NUT server) reaches **≤50% battery**, using **Home Assistant** as the orchestrator.

This replaces the built-in Synology NUT client, which has proven unreliable in this configuration.

---

## Architecture

```
Unifi UPS (NUT Server @ 10.20.30.5)
        │  NUT protocol (port 3493)
        ▼
Home Assistant — NUT integration
        │  monitors sensor.ups_battery_charge + sensor.ups_status
        ▼
HA Automation  (triggers: OB status AND battery ≤ 50%)
        │  SSH with key auth (30-second grace delay)
        ▼
Synology NAS (192.168.50.20) ← synoshutdown -h (graceful halt)
```

**Why this is more reliable than native Synology UPS support:**
- HA's NUT integration polls the UPS independently with built-in retry logic
- SSH key auth is stateless — no session, no token expiry
- The forced-command restriction on the SSH key means even a key leak cannot do more than initiate a shutdown
- A guard flag in HA prevents repeated shutdown commands if the battery oscillates near 50%

---

## Repository Layout

```
NASRemoteShutdown/
├── home_assistant/
│   └── nas_shutdown_package.yaml   # Drop into /config/packages/ on HA
├── nas_setup/
│   ├── generate_ssh_keypair.sh     # Run on HA host to create the SSH key
│   ├── 01_create_shutdown_user.sh  # Run on NAS to create ha_shutdown user
│   └── 02_sudoers_nas_shutdown     # Deploy to /etc/sudoers.d/ on NAS
└── tests/
    └── test_shutdown_trigger.sh    # Validate the setup without shutting down
```

---

## Setup — Step by Step

### Prerequisites

| Item | Requirement |
|------|-------------|
| Unifi UPS NUT port | TCP 3493 reachable from HA (10.20.30.5:3493) |
| NAS SSH port | TCP 22 reachable from HA (192.168.50.20:22) |
| HA config path | `/config` (standard HA OS / supervised) |
| NAS SSH enabled | DSM → Control Panel → Terminal & SNMP → SSH enabled |

---

### Step 1 — Generate the SSH keypair (run on HA host)

Open the HA SSH add-on terminal (or SSH into your HA host) and run:

```bash
bash nas_setup/generate_ssh_keypair.sh
```

This creates:
- `/config/.ssh/id_ed25519_ha_nas_shutdown` — **private key, stays on HA**
- `/config/.ssh/id_ed25519_ha_nas_shutdown.pub` — public key, copied to NAS in Step 2

Copy the displayed public key string to your clipboard.

---

### Step 2 — Create the shutdown user on the NAS

SSH into the NAS:

```bash
ssh admin@192.168.50.20
```

Transfer the setup script (or copy-paste it), then edit the `HA_PUBLIC_KEY` variable at the top of `01_create_shutdown_user.sh` with the public key from Step 1.

```bash
sudo bash 01_create_shutdown_user.sh
```

This creates a locked `ha_shutdown` user whose SSH key is restricted by a forced command (`synoshutdown -h`) — the key cannot be used for anything else.

---

### Step 3 — Deploy the sudoers rule on the NAS

Still on the NAS:

```bash
sudo cp 02_sudoers_nas_shutdown /etc/sudoers.d/ha_shutdown
sudo chmod 440 /etc/sudoers.d/ha_shutdown
sudo chown root:root /etc/sudoers.d/ha_shutdown
sudo visudo -c   # validate syntax — should print "parsed OK"
```

This allows `ha_shutdown` to run `/usr/syno/sbin/synoshutdown -h` without a password.

---

### Step 4 — Deploy the HA package

On the HA host:

```bash
# Enable packages support (add to configuration.yaml if not already there):
# homeassistant:
#   packages: !include_dir_named packages

mkdir -p /config/packages
cp home_assistant/nas_shutdown_package.yaml /config/packages/
```

> **If you already have a `nut:` block in configuration.yaml**, do not copy the `nut:` section — only copy the `shell_command:`, `input_boolean:`, and `automation:` blocks.

---

### Step 5 — Reload Home Assistant

In HA: **Settings → System → Restart** (or `ha core restart` from the CLI).

After restart, go to **Developer Tools → States** and search for `ups` — you should see:
- `sensor.ups_battery_charge` — a numeric value (e.g., `87`)
- `sensor.ups_status` — a string (`OL`, `OB`, or `LB`)

If these sensors don't appear, see [Troubleshooting](#troubleshooting) below.

---

### Step 6 — Validate with the test script

From the HA host:

```bash
bash tests/test_shutdown_trigger.sh
```

All four checks should pass:
1. SSH key exists with correct permissions
2. NAS is pingable
3. SSH port 22 is open on NAS
4. NUT port 3493 is open/queryable

---

### Step 7 — Live test (optional but recommended)

When you're ready to verify end-to-end (NAS will actually shut down):

1. Make sure all NAS workloads are idle / data is synced
2. Temporarily change `below: 51` to `below: 101` in the automation in HA
3. Set `sensor.ups_status` state to `OB` manually via **Developer Tools → States** (or unplug the UPS)
4. The automation fires — NAS should gracefully halt after 30 seconds
5. Power the NAS back on, then revert the threshold to `51`

---

## How It Works

### Trigger conditions (both must be true)

| Condition | Value | Reason |
|-----------|-------|--------|
| `sensor.ups_battery_charge` | `< 51` (i.e., ≤50%) | Your target threshold |
| `sensor.ups_status` | `OB` (On Battery) | Prevents false triggers when battery reads low during normal AC operation |
| `input_boolean.nas_shutdown_triggered` | `off` | Guard flag — prevents re-triggering during the shutdown sequence |

### Action sequence

1. Guard flag set to `on` (no re-triggers)
2. Persistent notification created in HA UI
3. **30-second grace delay** — lets running NAS processes complete
4. SSH command issued: `sudo /usr/syno/sbin/synoshutdown -h`
5. Confirmation notification created

### Power restore

When the UPS goes back online (`sensor.ups_status` → `OL`), the guard flag resets automatically so the next outage will trigger the shutdown again.

---

## Security Notes

- The `ha_shutdown` user has **no interactive shell** — it cannot be used for general SSH access
- The SSH authorized_keys entry uses a **forced command** — the key can only ever run `synoshutdown -h`, regardless of what command the SSH client requests
- The sudoers rule permits **only** `/usr/syno/sbin/synoshutdown -h` — no wildcards
- The private key never leaves the HA host; only the public key is on the NAS

---

## Troubleshooting

### UPS sensors not appearing in HA

- Verify the NUT port is reachable: `nc -zv 10.20.30.5 3493`
- Check the UPS name — it must match what the Unifi NUT server reports. Query it with:
  ```bash
  echo "LIST UPS" | nc 10.20.30.5 3493
  ```
  If the name shown is not `ups`, update the `alias:` line in `nas_shutdown_package.yaml` to match.
- Check HA logs: **Settings → System → Logs**, filter for `nut`

### SSH test fails / automation doesn't shut down NAS

- Verify `ha_shutdown` user exists on NAS: `id ha_shutdown`
- Check authorized_keys on NAS: `sudo cat /var/services/homes/ha_shutdown/.ssh/authorized_keys`
- Manually test SSH from HA (will trigger actual shutdown — do this only when ready):
  ```bash
  ssh -i /config/.ssh/id_ed25519_ha_nas_shutdown \
      -o StrictHostKeyChecking=no \
      ha_shutdown@192.168.50.20
  ```
- Check HA logs after the automation fires: look for `shell_command.shutdown_nas` output

### Automation fires but NAS doesn't shut down

- `synoshutdown` path may differ. Verify on NAS: `which synoshutdown`
- If the path is different, update both:
  - The `authorized_keys` forced command in `01_create_shutdown_user.sh`
  - The `02_sudoers_nas_shutdown` rule
  - The `shell_command.shutdown_nas` in `nas_shutdown_package.yaml`
- Check DSM system log for shutdown attempts: DSM → Log Center

### Guard flag stuck `on` after a test

Reset it manually: **Developer Tools → States → `input_boolean.nas_shutdown_triggered`** → set to `off`.
Or call the service: `input_boolean.turn_off` targeting `input_boolean.nas_shutdown_triggered`.
