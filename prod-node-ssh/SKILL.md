---
name: prod-node-ssh
description: Run READ-ONLY commands on a production IoT node by SSHing over the GCloud bastion (two-hop). Use when the MCP ssh tools refuse with StagingOnlyError, or whenever you need to inspect a prod node on-device — chrony/NTP, config files, network, logs, versions — and validate something the user did. Never run mutating commands.
---

# prod-node-ssh

SSH to a **production** node over the bastion to run **read-only** checks. The
`augury-iot-mcp` ssh tools are staging-only (`StagingOnlyError`), so prod
on-device inspection goes through this two-hop path instead.

## Hard rule: read-only

Only ever run commands that **read** state. This access is for inspection and
validation, not changes.

- **Allowed:** `cat`, `ls`, `head`, `tail`, `grep`, `chronyc sources`,
  `chronyc tracking`, `augury_ntp is_synced`, `augury_ntp get_sync_counter`,
  `augury_node_info`, `augury_network connections`, `augury_version`,
  `ip`/`ifconfig`, `uptime`, `df`, `free`, `ps`, reading files under `/data`,
  `/etc`, `/var/log`.
- **Never:** anything that writes or restarts — `rm`, `mv`, `cp`, `echo >`,
  `sed -i`, `tee`, `augury_ntp add_server|delete_all|set_time`, `systemctl`,
  `/etc/init.d/* restart|stop|start`, `reboot`, `augury_update`, `s6-*`, OTA,
  config pushes. If a change is needed, use the admin tool / proper MCP path,
  not this skill.

Before running, re-read the command and confirm it only reads. If unsure, don't.

## Prerequisite: gcloud auth

The bastion hop needs a live gcloud token. If a command fails with
*"Reauthentication failed / cannot prompt during non-interactive execution"*,
ask the user to run it themselves in-session:

```
! gcloud auth login
```

Then retry. Do not attempt `gcloud auth login` yourself — it's interactive.

## The command

Two-hop: gcloud SSH to the bastion, then SSH from the bastion to the node's
Tinc VPN IP as `augury`.

```bash
gcloud beta compute --project "development-6a969d7f" ssh --zone "us-east1-d" eyifrah@bastion \
  --command "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 augury@<NODE_TINC_IP> '<READ_ONLY_CMD>'"
```

`-o UserKnownHostsFile=/dev/null` avoids the "host key changed / offending key
in known_hosts" nag when a node has been re-imaged (harmless for read-only).

- `<NODE_TINC_IP>` — the node's VPN IP (`10.9.x.x` for Node2/Moxa/MP255,
  `10.10.x.x` for Cassia). Get it from the node list/sheet, or from BigQuery
  `latest_node_state.node_ip` (avoids Mongo). The MCP `get_node_tinc_ip` needs
  Mongo and may be down.
- Wrap the outer `--command` in double quotes, the inner remote command in
  single quotes. Keep `<READ_ONLY_CMD>` free of single quotes (chain with `;`).
- Wrap the whole thing in `timeout 120` — the bastion hop can be slow.
- Cassia SSHes on port `20022`: `ssh -p 20022 …`.

## Example — validate NTP config after an admin push

```bash
timeout 120 gcloud beta compute --project "development-6a969d7f" ssh --zone "us-east1-d" eyifrah@bastion \
  --command "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 augury@10.9.40.62 'echo ===DROPIN===; cat /data/chrony.d/chrony.conf; echo ===SOURCES===; chronyc sources -v'"
```

Expected for a `time.gaf.com` + pool push: five `server … iburst` lines in the
drop-in, and `chronyc sources` showing all five with `time.gaf.com` selected
(`^*`). The node applies a pushed config only after it polls cloud config and
restarts halo-node — allow a couple minutes.

## If the node is unreachable over Tinc

`ConnectTimeout`/no route usually means the node's Tinc hub is down or the node
is Europe-only. See the `node-tinc-isnt-working` flow (bring up the EU hub
`tinc-europe-west2-1`). Confirm the node is online first via BigQuery
`latest_node_state` (`mqtt_connected`, `timestamp` freshness).
