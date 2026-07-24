# AD Test Lab

Declarative Windows Active Directory test lab on NixOS using libvirt + QEMU/KVM.
Spin up Windows VMs, join them to a domain, test GPOs/PowerShell/scripts, then nuke them.

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│  NixOS Host (UwU / OwO-Family)                            │
│                                                          │
│  libvirt + QEMU/KVM                                       │
│  ┌─────────────────┐    ┌─────────────────┐              │
│  │ ad-dc1          │    │ ad-client1      │              │
│  │ Windows Server  │    │ Windows 10/11   │              │
│  │ 2022            │    │ (throwaway)     │              │
│  │                 │    │                 │              │
│  │ - AD DS (DC)    │    │ - joined to     │              │
│  │ - DNS           │    │   domain        │              │
│  │ - DHCP relay    │    │ - in OU         │              │
│  │ 192.168.100.10  │    │ 192.168.100.1xx │              │
│  └────────┬────────┘    └────────┬────────┘              │
│           │    ad-lab (NAT)      │                       │
│           │    192.168.100.0/24  │                       │
│           └──────────┬───────────┘                       │
│                      │                                   │
│  ┌───────────────────┴──────────────┐                    │
│  │  Optional: ad-bridge             │                    │
│  │  (bridged to physical NIC —       │                    │
│  │   for joining real ADs)           │                    │
│  └──────────────────────────────────┘                    │
└──────────────────────────────────────────────────────────┘
```

## Prerequisites

- NixOS with the `virtualisation` + `virtualisation-ad-lab` modules enabled
  (UwU and OwO-Family have them; TSBW-W01800 does not)
- Windows Server 2022 Eval ISO: https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2022
- Windows 10/11 Eval ISO: https://www.microsoft.com/en-us/software-download/
- At least 8GB free RAM (4GB DC + 4GB client) and ~100GB disk

## One-time setup

### 1. Rebuild to enable libvirt

```bash
just deploy
```

### 2. Create the domain controller (from ISO)

```bash
just lab-up
just lab-create-dc iso=~/Downloads/Server_2022.iso
```

Open `virt-manager` (GUI) to complete the Windows Server installation:
1. Install Windows Server 2022 (Desktop Experience recommended)
2. Set static IP to `192.168.100.10` (subnet `255.255.255.0`, DNS `127.0.0.1`)
3. Server Manager → Add Roles → AD DS → Promote to Domain Controller
4. Set domain name (e.g. `lab.local`)
5. Wait for installation + automatic reboot

After the DC is promoted and rebooted:

```bash
virsh snapshot-create-as ad-dc1 dc-base-snapshot
```

### 3. Create the client base image (from ISO)

```bash
just lab-create-client-base iso=~/Downloads/Win11.iso
```

Open `virt-manager` to install Windows 11:
1. Install Windows 11 Pro
2. Enable OpenSSH server (run in PowerShell as admin):
   ```powershell
   Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
   Start-Service sshd
   Set-Service -Name sshd -StartupType Automatic
   ```
3. (Optional) Enable RDP: `SystemPropertiesRemote → Allow remote connections`
4. Install virtio drivers (from the ISO or Windows Update)
5. Run sysprep: `C:\Windows\System32\Sysprep\sysprep.exe /generalize /oobe /shutdown`

After sysprep shuts down the VM:

```bash
virsh snapshot-create-as ad-client-base base-snapshot
```

## Daily workflow

### Start the lab

```bash
just lab-up
# → creates + starts the isolated NAT network
# → starts the domain controller VM
```

### Spin up a fresh client VM

```bash
just lab-fresh-client name=ad-client1
# → destroys old ad-client1 if it exists
# → generates temp SSH key at ~/.ssh/lab-keys/ad-client1/
# → clones from ad-client-base
# → injects SSH public key + enables OpenSSH
# → adds SSH config entry (ssh ad-client1 just works)
# → starts the VM
```

### Connect to the client

```bash
# SSH (PowerShell over SSH):
ssh ad-client1

# Or RDP (GUI):
virt-viewer ad-client1
# or find the VM's IP:
virsh domiflist ad-client1
xfreerdp /v:192.168.100.1xx /u:jaide
```

### Join the client to the domain

Copy the domain-join script into the VM, then run it:

```powershell
# The script is available on the host at /etc/ad-lab/domain-join.ps1
# Copy it to the VM via SSH:
#   scp /etc/ad-lab/domain-join.ps1 ad-client1:C:/Users/jaide/Desktop/

# Run in PowerShell as admin:
.\domain-join.ps1 -Domain "lab.local"
# Or with a specific OU:
.\domain-join.ps1 -Domain "lab.local" -OU "OU=Test,DC=lab,DC=local"

# Enter domain admin credentials when prompted. VM will restart.
```

### Test stuff

- GPOs — create them on the DC, they propagate to joined clients
- PowerShell scripts — test via SSH or RDP
- Registry changes, software deployment, NTFS ACLs, whatever you need
- The VM is a real Windows machine in a real AD — test anything

### Nuke the client (start fresh next time)

```bash
# Fastest: revert to snapshot (keeps same VM)
just lab-revert name=ad-client1

# Or: full clone (destroys old VM, creates fresh one)
just lab-fresh-client name=ad-client1

# Or: just delete it entirely
just lab-nuke name=ad-client1
# → destroys VM, deletes disk, removes SSH keys + config entry
```

### Join a real AD (outside the lab)

If you want to test against a real AD on the physical network:

```bash
just lab-bridge name=ad-client1
# → creates ad-bridge network (bridged to physical NIC)
# → hot-adds a bridged NIC to the VM
# → VM gets a real IP from the real DHCP
# → can now reach + join a real AD domain
```

The VM now has two NICs:
- `ad-lab` (NAT) — for the test lab network
- `ad-bridge` (bridged) — for the real network

### Shut it all down

```bash
just lab-down
# → shuts down all ad-* VMs
# → destroys the lab network
```

### Check lab status

```bash
just lab-status
# → shows network state
# → lists all lab VMs (running + stopped)
# → lists SSH keys for lab VMs
```

## Updating base images

When Windows needs updates or you want new tools in the base:

```bash
# Start the base VM
virsh start ad-client-base

# Windows Update, install tools, configure as desired via RDP/SSH
# When done, sysprep again:
#   C:\Windows\System32\Sysprep\sysprep.exe /generalize /oobe /shutdown

# After shutdown, update the snapshot:
virsh snapshot-delete ad-client-base base-snapshot
virsh snapshot-create-as ad-client-base base-snapshot
```

Do the same for `ad-dc1` if the DC needs updates (but be careful —
updating the DC changes the domain state).

## File locations

| What | Where |
|---|---|
| Lab network definitions | libvirt (created by `lab-net-create`) |
| VM disk images | `/var/lib/libvirt/images/` (default pool) |
| Temp SSH keys | `~/.ssh/lab-keys/<vm-name>/` |
| SSH config entries | `~/.ssh/config` |
| Domain-join PowerShell script | `/etc/ad-lab/domain-join.ps1` |
| NixOS modules | `modules/virtualisation/{libvirt,ad-lab}.nix` |

## Management scripts

All scripts are available as commands after rebuild (installed via NixOS):

| Script | What it does |
|---|---|
| `lab-net-create` | Create + start the isolated NAT network |
| `lab-net-destroy` | Destroy the lab network |
| `lab-net-bridge` | Create + start the bridged network |
| `lab-bridge-attach <vm>` | Hot-add a bridged NIC to a VM |
| `lab-create-dc [iso]` | Create the DC VM from ISO (one-time) |
| `lab-create-client-base [iso]` | Create the client base VM from ISO (one-time) |
| `lab-fresh-client <vm>` | Clone + temp SSH key + start |
| `lab-revert <vm>` | Revert to base snapshot + start |
| `lab-nuke <vm>` | Destroy VM + delete SSH keys + clean config |
| `lab-status` | Show network + VMs + SSH keys |

## Justfile shortcuts

| Command | What |
|---|---|
| `just lab-up` | Start network + DC |
| `just lab-down` | Shut down everything |
| `just lab-status` | Status overview |
| `just lab-create-dc iso=path` | Create DC from ISO |
| `just lab-create-client-base iso=path` | Create client base from ISO |
| `just lab-fresh-client name=ad-client1` | Fresh client VM |
| `just lab-revert name=ad-client1` | Revert to snapshot |
| `just lab-nuke name=ad-client1` | Destroy + clean up |
| `just lab-bridge name=ad-client1` | Attach bridged NIC |

## Multiple clients

You can run multiple clients at once — just use different names:

```bash
just lab-fresh-client name=ad-client1
just lab-fresh-client name=ad-client2
just lab-fresh-client name=ad-client3
```

Each gets its own SSH key, IP, and disk. Nuke them individually or all at
once with `just lab-down`.

## Troubleshooting

### virt-customize can't inject SSH key

If `lab-fresh-client` says "virt-customize could not inject key", the
Windows image might not be readable by libguestfs. Fix manually:

1. RDP/SSH into the VM after it boots
2. Run PowerShell as admin:
   ```powershell
   Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
   Start-Service sshd
   Set-Service -Name sshd -StartupType Automatic
   ```
3. Copy your temp public key to `C:\ProgramData\ssh\administrators_authorized_keys`

### VM won't boot from ISO

Make sure you're using the right `--os-variant`. Check available variants:
```bash
osinfo-query os | grep -i windows
```

### Can't reach the VM via SSH

Check the VM's IP:
```bash
virsh domiflist ad-client1
# or
virsh net-dhcp-leases ad-lab
```

Then SSH directly:
```bash
ssh -i ~/.ssh/lab-keys/ad-client1/id_ed25519 jaide@192.168.100.1xx
```

### Nested virtualisation

If you need to run VMs inside a VM (e.g. testing Hyper-V), nested virt is
enabled for AMD hosts. For Intel, add to the host config:
```nix
boot.extraModprobeConfig = "options kvm_intel nested=1";
```