# ansible-role-proxmox-networking

Installs and configures the base Open vSwitch network stack on a Proxmox VE
host — an OVS bond with a bridge on top for the common case, or a single-NIC
fallback for hosts that only have one physical interface. This is the layer
[`ansible-role-proxmox-sdn`](../ansible-role-proxmox-sdn) builds Proxmox SDN
zones/vnets on top of; run this role first.

Designed to be run from a portable control environment (e.g. a USB stick) —
see [Bootstrap](#bootstrap) below.

## Requirements

- Proxmox VE 8.x (Debian bookworm) target hosts, reachable over SSH as (or
  via sudo to) root.
- [`uv`](https://docs.astral.sh/uv/) on the control machine, to build the
  pinned Python 3.13.5 virtualenv this role runs from.
- `ansible-core` is *not* required to be pre-installed on the control
  machine — the bootstrap script installs it into the venv.

## Bootstrap

```sh
./bootstrap/bootstrap.sh
source .venv/bin/activate
```

The venv is a compiled artifact tied to whatever machine built it — it is
**not** portable across different host machines/architectures even though it
lives on a portable stick. `bootstrap.sh` is idempotent and fast to re-run:
plug the stick into a different machine and run it again; it only rebuilds
when the venv is missing or on the wrong Python version.

## Role Variables

All variables live in `defaults/main.yml`. The most important ones:

| Variable | Default | Description |
|---|---|---|
| `proxmox_net_mode` | `bond` | `bond` or `single_nic` — explicit, not inferred. |
| `proxmox_net_bond_name` | `bond0` | OVS bond interface name (mode: bond). |
| `proxmox_net_bond_interfaces` | `[]` | Physical NICs to bond, >=2 entries required (mode: bond). |
| `proxmox_net_bond_mode` | `balance-slb` | OVS bond mode: `active-backup`, `balance-slb`, `balance-tcp`. |
| `proxmox_net_bond_lacp` | `false` | Set `true` for LACP (needs `balance-tcp` + switch-side LACP config). |
| `proxmox_net_single_interface` | `""` | Physical NIC to use directly (mode: single_nic). |
| `proxmox_net_bridge_name` | `vmbr0` | OVS bridge name — this is what the SDN role's zones attach to. |
| `proxmox_net_mgmt_ip` | `""` | Node's management IP in CIDR form — **per-node, set in host_vars.** |
| `proxmox_net_mgmt_gateway` | `""` | Node's management gateway — per-node. |
| `proxmox_net_mgmt_vlan` | `0` | `0` = untagged on the bridge; otherwise creates a tagged mgmt sub-interface. |
| `proxmox_net_apply_changes` | `true` | `false` = render + validate only, no live `ifreload -a`. |
| `proxmox_net_revert_on_failure` | `true` | `true` = arm autonomous host watchdog to revert if network fails. |
| `proxmox_net_revert_timeout` | `30` | Seconds to wait for clean network confirmation before reverting. |
| `proxmox_net_safety_check_ping_gateway` | `true` | `true` = ping `proxmox_net_mgmt_gateway` as a health gate. |
| `proxmox_net_wait_for_connection_timeout` | `60` | Connection recovery timeout (allows host watchdog to finish reverting). |

See `examples/group_vars/proxmox.yml` and `examples/host_vars/` for a
worked bonded example and a single-NIC example.

## Example Playbook

Bare role names (`ansible-role-proxmox-networking`) only resolve if
`roles_path` points at the parent directory both role repos live in —
`examples/ansible.cfg.example` sets that up. Recommended layout: put your
real `site.yml`/`inventory.ini`/`ansible.cfg` one level up, as a sibling of
both role repos:

```sh
cd ..   # the directory containing both ansible-role-proxmox-* repos
cp ansible-role-proxmox-networking/examples/ansible.cfg.example ansible.cfg
cp ansible-role-proxmox-networking/examples/inventory.example.ini inventory.ini   # edit hostnames/IPs
cp -r ansible-role-proxmox-networking/examples/group_vars ansible-role-proxmox-networking/examples/host_vars .   # edit topology + per-node IPs
cp ansible-role-proxmox-networking/examples/site.yml.example site.yml

ansible-role-proxmox-networking/.venv/bin/ansible-playbook -i inventory.ini site.yml --check --diff   # review first
ansible-role-proxmox-networking/.venv/bin/ansible-playbook -i inventory.ini site.yml
```

## Safety

This role reconfigures the network interface Ansible is connected through.
It takes several precautions, including an **autonomous 30-second rollback watchdog**:

1. The rendered `/etc/network/interfaces` is validated (`ifquery -i <candidate> -a`,
   which parses every stanza in the candidate file — `ifreload` itself has
   no way to target a not-yet-live candidate file, only `ifquery` does)
   before it's ever written — a bad config fails the task closed, not open.
2. The working pre-change configuration is saved to
   `/etc/network/interfaces.ansible-rollback` (in addition to standard
   timestamped `backup: true`).
3. An autonomous watchdog (`/usr/local/sbin/proxmox-net-rollback arm 30`) is
   armed as a detached systemd service (`systemd-run`) before reloading.
4. Changes are applied via `ifreload -a` (ifupdown2's live, non-disruptive reload).
5. **Revert on Isolation**: If connectivity is completely severed and Ansible
   cannot reconnect within 30 seconds, the host-side watchdog autonomously
   restores `/etc/network/interfaces` from the rollback backup, runs `ifreload -a`,
   and brings the node back online. Ansible's `wait_for_connection` reconnects,
   detects the rollback marker (`/run/proxmox-net-reverted`), and fails the play
   with full diagnostic details.
6. **Revert on Safety Check Failure**: If the host reconnects within 30 seconds
   but fails live health checks (bridge interface not UP, management IP not bound,
   or management gateway unreachable via ping), Ansible triggers an immediate
   rollback (`proxmox-net-rollback revert`) and fails with the exact reason.
7. If all health checks pass cleanly, the watchdog is disarmed and the change is
   permanently committed.
8. Set `proxmox_net_apply_changes: false` to render and validate only on a
   node's first run, and review the diff before ever reloading its live
   network.

Recommended rollout: `serial: 1` (see `examples/site.yml.example`), one node
at a time.

## Roadmap

- vnet firewall configuration is **not** part of this role — see
  [`ansible-role-proxmox-sdn`](../ansible-role-proxmox-sdn)'s
  `docs/roadmap.md`.
