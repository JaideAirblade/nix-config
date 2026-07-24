# AD test lab — isolated libvirt network + bridge option + VM management scripts.
#
# Two network modes:
#   ad-lab    — isolated NAT (192.168.100.0/24), VMs in their own world
#   ad-bridge — bridged to physical NIC, VMs get real IPs for real-AD testing
#
# Each client VM gets a temporary SSH keypair at ~/.ssh/lab-keys/<vm-name>/
# that is deleted when the VM is nuked. The public key is injected via
# virt-customize + OpenSSH server is enabled in the Windows image.
{ pkgs, lib, ... }:

{
  # ── Lab network management scripts ────────────────────────────────
  # These create/destroy the libvirt networks. The isolated NAT network
  # is the default; the bridge is opt-in per-VM.
  environment.systemPackages = [
    # Create + start the isolated lab network
    (pkgs.writeShellScriptBin "lab-net-create" ''
      set -e
      if ! virsh net-info ad-lab >/dev/null 2>&1; then
        echo "Creating AD lab network ad-lab (192.168.100.0/24)..."
        cat <<'XML' | virsh net-define /dev/stdin
      <network>
        <name>ad-lab</name>
        <forward mode="nat"/>
        <ip address="192.168.100.1" prefix="24">
          <dhcp>
            <range start="192.168.100.100" end="192.168.100.200"/>
          </dhcp>
        </ip>
      </network>
      XML
      fi
      virsh net-start ad-lab 2>/dev/null || true
      virsh net-autostart ad-lab 2>/dev/null || true
      echo "Lab network ad-lab is up (192.168.100.0/24, NAT)"
    '')

    # Destroy the lab network
    (pkgs.writeShellScriptBin "lab-net-destroy" ''
      virsh net-destroy ad-lab 2>/dev/null || true
      virsh net-undefine ad-lab 2>/dev/null || true
      echo "Lab network ad-lab destroyed"
    '')

    # Create the bridged network (for joining real ADs)
    # Uses the first physical bridge or creates one on the fly
    (pkgs.writeShellScriptBin "lab-net-bridge" ''
      set -e
      # Find the default network (libvirt's default is usually bridged)
      if ! virsh net-info ad-bridge >/dev/null 2>&1; then
        echo "Creating bridged network ad-bridge..."
        # Find a physical interface to bridge to
        IFACE=$(ip -o link show | grep -v 'lo\|virbr\|vnet\|tap\|docker\|br-' | awk -F': ' '{print $2}' | head -1)
        if [ -z "$IFACE" ]; then
          echo "ERROR: No physical interface found for bridge"
          exit 1
        fi
        echo "Bridging to interface: $IFACE"
        cat <<XML | virsh net-define /dev/stdin
      <network>
        <name>ad-bridge</name>
        <forward mode="bridge"/>
        <bridge name="virbr-ad"/>
      </network>
      XML
      fi
      virsh net-start ad-bridge 2>/dev/null || true
      virsh net-autostart ad-bridge 2>/dev/null || true
      echo "Bridged network ad-bridge is up (VMs get real IPs)"
    '')

    # Hot-add a bridged NIC to a running VM (for joining real ADs)
    (pkgs.writeShellScriptBin "lab-bridge-attach" ''
      VM="''${1:?Usage: lab-bridge-attach <vm-name>}"
      if ! virsh dominfo "$VM" >/dev/null 2>&1; then
        echo "ERROR: VM $VM not found"
        exit 1
      fi
      lab-net-bridge
      # Find next available slot in the VM
      LAST=$(virsh domiflist "$VM" 2>/dev/null | tail -n +3 | wc -l)
      virsh attach-interface "$VM" network ad-bridge --model virtio --persistent 2>/dev/null || \
      virsh attach-interface "$VM" network ad-bridge --model virtio --live
      echo "Bridged NIC added to $VM. New interface will get a real DHCP IP."
      echo "Check with: virsh domiflist $VM"
    '')

    # ── VM creation + management scripts ──────────────────────────────
    # Domain controller creation (one-time, from ISO)
    (pkgs.writeShellScriptBin "lab-create-dc" ''
      set -euo pipefail
      ISO="''${1:-$HOME/Downloads/Windows_Server_2022_EVAL_x64.iso}"
      VM_NAME="ad-dc1"

      if virsh dominfo "$VM_NAME" >/dev/null 2>&1; then
        echo "VM $VM_NAME already exists. Use 'just lab-up' to start it."
        exit 0
      fi

      if [ ! -f "$ISO" ]; then
        echo "ERROR: ISO not found at $ISO"
        echo "Pass the ISO path as argument: lab-create-dc /path/to/iso"
        exit 1
      fi

      lab-net-create
      echo "Creating DC VM $VM_NAME from $ISO..."
      virt-install \
        --name "$VM_NAME" \
        --network network=ad-lab \
        --memory 4096 \
        --vcpus 4 \
        --os-variant win2k22 \
        --disk size=60,bus=virtio,format=qcow2,pool=default \
        --cdrom "$ISO" \
        --graphics spice \
        --boot uefi \
        --noautoconsole

      echo ""
      echo "DC VM created. Open virt-manager to install Windows Server."
      echo "After install + promoting to DC, snapshot it:"
      echo "  virsh snapshot-create-as $VM_NAME dc-base-snapshot"
    '')

    # Client base image creation (one-time, from ISO)
    (pkgs.writeShellScriptBin "lab-create-client-base" ''
      set -euo pipefail
      ISO="''${1:-$HOME/Downloads/Windows_11_EVAL_x64.iso}"
      VM_NAME="ad-client-base"

      if virsh dominfo "$VM_NAME" >/dev/null 2>&1; then
        echo "Base VM $VM_NAME already exists."
        exit 0
      fi

      if [ ! -f "$ISO" ]; then
        echo "ERROR: ISO not found at $ISO"
        echo "Pass the ISO path as argument: lab-create-client-base /path/to/iso"
        exit 1
      fi

      lab-net-create
      echo "Creating client base VM $VM_NAME from $ISO..."
      virt-install \
        --name "$VM_NAME" \
        --network network=ad-lab \
        --memory 4096 \
        --vcpus 4 \
        --os-variant win11 \
        --disk size=40,bus=virtio,format=qcow2,pool=default \
        --cdrom "$ISO" \
        --graphics spice \
        --boot uefi \
        --noautoconsole

      echo ""
      echo "Client base VM created. Open virt-manager to install Windows."
      echo "After install:"
      echo "  1. Enable OpenSSH server: Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0"
      echo "  2. Start sshd: Start-Service sshd; Set-Service -Name sshd -StartupType Automatic"
      echo "  3. Run sysprep: sysprep /generalize /oobe /shutdown"
      echo "  4. After shutdown, snapshot: virsh snapshot-create-as $VM_NAME base-snapshot"
    '')

    # Create a fresh client VM from base image + generate temp SSH key
    (pkgs.writeShellScriptBin "lab-fresh-client" ''
      set -euo pipefail
      VM_NAME="''${1:?Usage: lab-fresh-client <vm-name>}"
      BASE="ad-client-base"
      KEY_DIR="$HOME/.ssh/lab-keys/$VM_NAME"

      # Nuke old VM if it exists
      virsh destroy "$VM_NAME" 2>/dev/null || true
      virsh undefine "$VM_NAME" --remove-all-storage 2>/dev/null || true

      # Clean old SSH keys
      rm -rf "$KEY_DIR"

      # Generate temp SSH keypair
      mkdir -p "$KEY_DIR"
      ssh-keygen -t ed25519 -C "lab-$VM_NAME" -f "$KEY_DIR/id_ed25519" -N ""
      chmod 600 "$KEY_DIR/id_ed25519"

      # Clone from base image
      echo "Cloning $VM_NAME from $BASE..."
      virt-clone --name "$VM_NAME" --original "$BASE" --auto-clone

      # Inject SSH public key + enable OpenSSH (if guest tools available)
      PUBKEY=$(cat "$KEY_DIR/id_ed25519.pub")
      # Try virt-customize (works if libguestfs can read the image)
      virt-customize -d "$VM_NAME" \
        --mkdir "/ProgramData/ssh" \
        --write "/ProgramData/ssh/administrators_authorized_keys:$PUBKEY" \
        --run-command 'powershell -Command "Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0; Start-Service sshd; Set-Service -Name sshd -StartupType Automatic"' \
        2>/dev/null || echo "NOTE: virt-customize could not inject key. Use RDP to set up SSH manually."

      # Add SSH config entry
      grep -q "Host $VM_NAME" "$HOME/.ssh/config" 2>/dev/null || cat >> "$HOME/.ssh/config" <<SSHCFG

Host $VM_NAME
  HostName 192.168.100.$((100 + RANDOM % 100))
  User jaide
  IdentityFile $KEY_DIR/id_ed25519
  StrictHostKeyChecking accept-new
SSHCFG

      # Start the VM
      virsh start "$VM_NAME"
      echo ""
      echo "VM $VM_NAME created and started."
      echo "  SSH key: $KEY_DIR/id_ed25519"
      echo "  SSH: ssh $VM_NAME (after VM boots + gets DHCP IP)"
      echo "  RDP: virt-viewer $VM_NAME or xfreerdp /v:<vm-ip>"
      echo ""
      echo "  Nuke when done: lab-nuke $VM_NAME"
    '')

    # Revert a client VM to its base snapshot (faster than fresh clone)
    (pkgs.writeShellScriptBin "lab-revert" ''
      set -e
      VM_NAME="''${1:?Usage: lab-revert <vm-name>}"
      virsh snapshot-revert "$VM_NAME" base-snapshot 2>/dev/null || {
        echo "No base-snapshot found for $VM_NAME. Use lab-fresh-client instead."
        exit 1
      }
      virsh start "$VM_NAME"
      echo "VM $VM_NAME reverted to base snapshot and started."
    '')

    # Nuke a client VM + clean up SSH keys
    (pkgs.writeShellScriptBin "lab-nuke" ''
      set -e
      VM_NAME="''${1:?Usage: lab-nuke <vm-name>}"
      virsh destroy "$VM_NAME" 2>/dev/null || true
      virsh undefine "$VM_NAME" --remove-all-storage 2>/dev/null || true
      rm -rf "$HOME/.ssh/lab-keys/$VM_NAME"
      # Remove SSH config entry
      sed -i "/^Host $VM_NAME$/,/^\$/d" "$HOME/.ssh/config" 2>/dev/null || true
      echo "VM $VM_NAME nuked. SSH keys + config cleaned up."
    '')

    # Lab status — show network + VMs
    (pkgs.writeShellScriptBin "lab-status" ''
      echo "═══ AD Lab Status ═══"
      echo ""
      echo "── Network ──"
      virsh net-info ad-lab 2>/dev/null || echo "  ad-lab: not created"
      echo ""
      echo "── VMs ──"
      virsh list --all 2>/dev/null | grep '^ad-' || echo "  no lab VMs"
      echo ""
      echo "── SSH Keys ──"
      ls -1 "$HOME/.ssh/lab-keys/" 2>/dev/null || echo "  none"
    '')
  ];

  # ── PowerShell domain-join script (available at /etc/ad-lab/) ──────
  environment.etc."ad-lab/domain-join.ps1".text = ''
    # Join the AD domain and optionally place in a specified OU.
    # Usage (from within the VM):
    #   .\domain-join.ps1 -Domain "lab.local"
    #   .\domain-join.ps1 -Domain "lab.local" -OU "OU=Test,DC=lab,DC=local"

    param(
      [Parameter(Mandatory=$true)]
      [string]$Domain,

      [Parameter(Mandatory=$false)]
      [string]$OU
    )

    # Set DNS to point to DC
    $adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
    $dcIP = "192.168.100.10"

    Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses $dcIP

    # Join domain
    if ($OU) {
      Add-Computer -DomainName $Domain -OUPath $OU -Credential (Get-Credential) -Restart -Force
    } else {
      Add-Computer -DomainName $Domain -Credential (Get-Credential) -Restart -Force
    }

    Write-Host "Joined domain $Domain. VM will restart."
  '';

  # QEMU guest agent — installed on host for clean VM shutdown.
  # VMs need to install it separately inside Windows.
}