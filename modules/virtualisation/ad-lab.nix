# AD test lab — isolated libvirt network + bridge option + VM management scripts.
#
# Two network modes:
#   ad-lab — isolated (192.168.100.0/24), VMs in their own world
#   direct — an explicitly selected physical NIC for real-AD testing
#
# Each client VM gets a temporary SSH keypair at ~/.ssh/lab-keys/<vm-name>/
# that is deleted when the VM is nuked. The public key is injected via
# virt-customize + OpenSSH server is enabled in the Windows image.
_:
{
  nixos.modules.adLab =
    { pkgs, ... }:
    let
      # These names are used in virsh commands, SSH-config regexes, and
      # recursive key-directory removal. Keep them inside the AD-lab namespace
      # and refuse the two irreplaceable template/DC domains.
      validateLabClientName = ''
        validate_lab_client_name() {
          local name="$1"
          if [[ ! "$name" =~ ^ad-[A-Za-z0-9][A-Za-z0-9_-]*$ ]]; then
            echo "ERROR: VM name must match ^ad-[A-Za-z0-9][A-Za-z0-9_-]*$" >&2
            exit 2
          fi
          case "$name" in
            ad-dc1|ad-client-base)
              echo "ERROR: refusing destructive client operation on reserved VM $name" >&2
              exit 2
              ;;
          esac
        }
      '';
    in
    {
      # ── AD attack tools + lab management scripts ───────────────────────
      # Attack tools complement the impacket/evil-winrm/netexec tools from
      # windows-tools.nix. They're in the ad-lab module because they're
      # only useful with a running AD lab.
      environment.systemPackages = with pkgs; [
        # --- AD attack tools ---
        responder # LLMNR/NBT-NS poisoner — capture NTLMv2 hashes from AD clients
        bloodhound # AD attack path visualization — maps the whole domain graph
        mitm6 # IPv6 DNS takeover — forces AD hosts to use your DNS server

        # --- Lab network management scripts ---
        # These create/destroy the libvirt networks. The isolated network is
        # the default; direct physical access is opt-in per VM.
        # Create + start the isolated lab network
        (pkgs.writeShellScriptBin "lab-net-create" ''
          set -e
          if ! virsh net-info ad-lab >/dev/null 2>&1; then
            echo "Creating AD lab network ad-lab (192.168.100.0/24)..."
            cat <<'XML' | virsh net-define /dev/stdin
          <network>
            <name>ad-lab</name>
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
          echo "Lab network ad-lab is up (192.168.100.0/24, isolated)"
        '')

        # Destroy the lab network
        (pkgs.writeShellScriptBin "lab-net-destroy" ''
          virsh net-destroy ad-lab 2>/dev/null || true
          virsh net-undefine ad-lab 2>/dev/null || true
          echo "Lab network ad-lab destroyed"
        '')

        # Hot-add a macvtap NIC on an explicitly selected physical interface.
        # Requiring the interface avoids silently exposing a hostile lab VM on
        # whichever adapter happened to sort first.
        (pkgs.writeShellScriptBin "lab-bridge-attach" ''
          set -euo pipefail
          VM="''${1:?Usage: lab-bridge-attach <vm-name> <physical-interface>}"
          IFACE="''${2:?Usage: lab-bridge-attach <vm-name> <physical-interface>}"
          if ! virsh dominfo "$VM" >/dev/null 2>&1; then
            echo "ERROR: VM $VM not found"
            exit 1
          fi
          if [ ! -e "/sys/class/net/$IFACE" ]; then
            echo "ERROR: interface $IFACE does not exist"
            exit 1
          fi
          virsh attach-interface "$VM" direct "$IFACE" --source-mode bridge \
            --model virtio --persistent --live
          echo "Direct NIC on $IFACE added to $VM. The VM is now exposed to that network."
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

        # ── Print server VM creation (NixOS, from this flake) ──────
        # Creates a NixOS VM in the ad-lab network at 192.168.100.20.
        # The VM disk image is built from this flake's Projet-Printserver
        # config via `nixos-rebuild build-vm`, then imported into libvirt.
        # After first boot, SSH in and run `realm join lab.local`.
        (pkgs.writeShellScriptBin "lab-create-printserver" ''
          set -euo pipefail
          VM_NAME="Projet-Printserver"
          FLAKE_DIR="''${1:-$(git rev-parse --show-toplevel 2>/dev/null || echo "$HOME/nixos")}"

          if virsh dominfo "$VM_NAME" >/dev/null 2>&1; then
            echo "VM $VM_NAME already exists. Use 'virsh start $VM_NAME' to start it."
            exit 0
          fi

          lab-net-create

          # Build the VM disk image from the flake. This produces a
          # nixos.qcow2 disk image with the bootloader and NixOS installed.
          echo "Building Projet-Printserver VM image from flake..."
          VM_RESULT=$(mktemp -d)
          nix build "$FLAKE_DIR#nixosConfigurations.Projet-Printserver.config.system.build.vm" \
            --out-link "$VM_RESULT/result" 2>&1

          # The build produces a symlink to a directory containing
          # nixos.qcow2 (the disk image) and run-vm (the launch script).
          DISK_IMG="$VM_RESULT/result/nixos.qcow2"
          if [ ! -f "$DISK_IMG" ]; then
            echo "ERROR: VM disk image not found at $DISK_IMG"
            echo "Build output:"
            ls -la "$VM_RESULT/result/"
            exit 1
          fi

          # Create a writable copy of the disk image for libvirt.
          VM_DISK="/var/lib/libvirt/images/$VM_NAME.qcow2"
          sudo mkdir -p "$(dirname "$VM_DISK")"
          sudo cp "$DISK_IMG" "$VM_DISK"
          sudo chown libvirtd:libvirtd "$VM_DISK" 2>/dev/null || true

          # Create the VM with virt-install, using the flake-built disk.
          # The VM uses the ad-lab network (192.168.100.0/24).
          # The static IP (192.168.100.20) is set in the NixOS config.
          echo "Creating print server VM $VM_NAME..."
          virt-install \
            --name "$VM_NAME" \
            --network network=ad-lab \
            --memory 2048 \
            --vcpus 2 \
            --os-variant nixos-25.05 \
            --disk path="$VM_DISK",bus=virtio,format=qcow2 \
            --import \
            --graphics spice \
            --noautoconsole

          echo ""
          echo "Print server VM $VM_NAME created and started."
          echo "  IP: 192.168.100.20 (static, from NixOS config)"
          echo "  SSH: ssh root@192.168.100.20"
          echo ""
          echo "  Next steps:"
          echo "    1. SSH in: ssh root@192.168.100.20"
          echo "    2. Join AD: realm join lab.local -U Administrator"
          echo "    3. Verify: id administrator && getent group 'Domain Admins'"
          echo "    4. Add admin to lpadmin: usermod -aG lpadmin administrator"
          echo "    5. Redeploy: just deploy Projet-Printserver"
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
                ${validateLabClientName}
                validate_lab_client_name "$VM_NAME"
                BASE="ad-client-base"
                KEY_ROOT="$HOME/.ssh/lab-keys"
                KEY_DIR="$KEY_ROOT/$VM_NAME"

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
          set -euo pipefail
          VM_NAME="''${1:?Usage: lab-revert <vm-name>}"
          ${validateLabClientName}
          validate_lab_client_name "$VM_NAME"
          virsh snapshot-revert "$VM_NAME" base-snapshot 2>/dev/null || {
            echo "No base-snapshot found for $VM_NAME. Use lab-fresh-client instead."
            exit 1
          }
          virsh start "$VM_NAME"
          echo "VM $VM_NAME reverted to base snapshot and started."
        '')

        # Nuke a client VM + clean up SSH keys
        (pkgs.writeShellScriptBin "lab-nuke" ''
          set -euo pipefail
          VM_NAME="''${1:?Usage: lab-nuke <vm-name>}"
          ${validateLabClientName}
          validate_lab_client_name "$VM_NAME"
          virsh destroy "$VM_NAME" 2>/dev/null || true
          virsh undefine "$VM_NAME" --remove-all-storage 2>/dev/null || true
          KEY_ROOT="$HOME/.ssh/lab-keys"
          rm -rf -- "$KEY_ROOT/$VM_NAME"
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
  ;
}
