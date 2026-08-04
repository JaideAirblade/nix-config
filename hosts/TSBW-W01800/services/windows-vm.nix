# Windows VM for TSBW-W01800 — bridged to the Thunderbolt dock NIC (enp1s0)
# for joining the real ausbildung.tsbw.de AD domain.
#
# The VM gets a real IP from the TSBW DHCP server, can reach the real AD DCs,
# and is visually accessible in a browser via noVNC (websockify + QEMU VNC).
#
# Network: macvtap bridge on enp1s0 (ThinkPad Thunderbolt 3 Dock ethernet).
#   The dock NIC must be UP and carrying the tsbw.de network (cable plugged in).
#   macvtap gives the VM a real MAC + real DHCP lease without exposing the host.
_:
{
  nixos.hosts."TSBW-W01800" =
    { pkgs, ... }:
    let
      # The physical NIC the VM bridges to. enp1s0 = RTL8111 PCIe ethernet
      # behind the ThinkPad Thunderbolt 3 Dock.
      bridgeIface = "enp1s0";

      # noVNC web port — browse to http://localhost:6080/vnc.html
      novncPort = 6080;

      # QEMU VNC display port (5900 = display :0). noVNC proxies this to HTTP.
      vncDisplay = 0;
    in
    {
      # ── noVNC: browser-based VM console ───────────────────────────────
      # websockify bridges QEMU's VNC socket to a WebSocket so noVNC's HTML5
      # client can connect from a browser.  A systemd service starts
      # websockify on demand (after libvirtd) and serves the noVNC web app.
      systemd.services.novnc = {
        description = "noVNC web client (browser access to Windows VM)";
        after = [ "libvirtd.service" "network.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs.novnc}/bin/novnc"
            + " --listen ${toString novncPort}"
            + " --vnc localhost:${toString (5900 + vncDisplay)}";
          Restart = "on-failure";
          RestartSec = "3s";
        };
      };

      # ── VM management scripts ─────────────────────────────────────────
      environment.systemPackages = with pkgs; [
        # Tools needed by the scripts below
        libguestfs # virt-customize, virt-clone
        bridge-utils # brctl — for debugging macvtap

        # Create the Windows VM bridged to the Thunderbolt dock NIC.
        # The VM boots from ISO, installs Windows, and gets a real IP from
        # the TSBW DHCP server via macvtap on enp1s0.
        (pkgs.writeShellScriptBin "tsbw-vm-create" ''
          set -euo pipefail
          ISO="''${1:-$HOME/Downloads/Windows_11_EVAL_x64.iso}"
          VM_NAME="tsbw-win"
          VNC_PORT=$((5900 + ${toString vncDisplay}))

          if virsh dominfo "$VM_NAME" >/dev/null 2>&1; then
            echo "VM $VM_NAME already exists. Start it with: tsbw-vm-start"
            exit 0
          fi

          if [ ! -f "$ISO" ]; then
            echo "ERROR: ISO not found at $ISO"
            echo "Pass the ISO path: tsbw-vm-create /path/to/windows.iso"
            echo "Download Windows 11 Eval:"
            echo "  https://www.microsoft.com/en-us/software-download/windows11"
            exit 1
          fi

          if [ ! -e "/sys/class/net/${bridgeIface}" ]; then
            echo "ERROR: bridge interface ${bridgeIface} does not exist"
            echo "Is the Thunderbolt dock connected?"
            exit 1
          fi

          # Check the dock NIC has carrier (cable plugged in)
          if [ "$(cat /sys/class/net/${bridgeIface}/operstate 2>/dev/null)" != "up" ]; then
            echo "WARNING: ${bridgeIface} is not up (no cable?)."
            echo "The VM will still be created but won't get a DHCP lease."
            echo "Plug an ethernet cable into the dock and run tsbw-vm-start."
          fi

          echo "Creating Windows VM '$VM_NAME' bridged to ${bridgeIface}..."
          virt-install \
            --name "$VM_NAME" \
            --network "bridge:virbr0,model=virtio" \
            --memory 8192 \
            --vcpus 4 \
            --os-variant win11 \
            --disk size=60,bus=virtio,format=qcow2,pool=default \
            --cdrom "$ISO" \
            --graphics vnc,listen=0.0.0.0,port=$VNC_PORT \
            --boot uefi \
            --noautoconsole

          echo ""
          echo "VM '$VM_NAME' created and started."
          echo ""
          echo "  Visual access (browser):  http://localhost:${toString novncPort}/vnc.html"
          echo "  Visual access (VNC):      vncviewer localhost:$VNC_PORT"
          echo ""
          echo "Next steps:"
          echo "  1. Open the browser URL above to install Windows"
          echo "  2. After Windows setup, run the domain-join script:"
          echo "     scp /etc/tsbw-vm/domain-join.ps1 and run it in PowerShell"
        '')

        # Start the VM
        (pkgs.writeShellScriptBin "tsbw-vm-start" ''
          set -euo pipefail
          VM_NAME="tsbw-win"
          if ! virsh dominfo "$VM_NAME" >/dev/null 2>&1; then
            echo "ERROR: VM $VM_NAME not found. Create with: tsbw-vm-create"
            exit 1
          fi
          virsh start "$VM_NAME"
          echo "VM $VM_NAME started."
          echo "  Browser: http://localhost:${toString novncPort}/vnc.html"
          echo "  VNC:     vncviewer localhost:$((5900 + ${toString vncDisplay}))"
        '')

        # Stop the VM (graceful shutdown)
        (pkgs.writeShellScriptBin "tsbw-vm-stop" ''
          set -euo pipefail
          VM_NAME="tsbw-win"
          virsh shutdown "$VM_NAME" 2>/dev/null && echo "VM $VM_NAME shutting down." || echo "VM $VM_NAME not running."
        '')

        # Connect the VM's NIC to the physical bridge (after first boot)
        (pkgs.writeShellScriptBin "tsbw-vm-bridge" ''
          set -euo pipefail
          VM_NAME="tsbw-win"
          IFACE="''${1:-${bridgeIface}}"

          if ! virsh dominfo "$VM_NAME" >/dev/null 2>&1; then
            echo "ERROR: VM $VM_NAME not found."
            exit 1
          fi
          if [ ! -e "/sys/class/net/$IFACE" ]; then
            echo "ERROR: interface $IFACE does not exist"
            exit 1
          fi

          # Hot-add a macvtap NIC on the physical interface
          virsh attach-interface "$VM_NAME" direct "$IFACE" \
            --model virtio --persistent --live 2>/dev/null || \
          virsh attach-interface "$VM_NAME" direct "$IFACE" \
            --model virtio --persistent
          echo "Bridged NIC on $IFACE added to $VM_NAME."
          echo "The VM will get a real IP from the TSBW DHCP server."
          echo "Check with: virsh domiflist $VM_NAME"
        '')

        # Show VM status + IP + noVNC URL
        (pkgs.writeShellScriptBin "tsbw-vm-status" ''
          VM_NAME="tsbw-win"
          echo "═══ TSBW Windows VM Status ═══"
          echo ""
          echo "── VM ──"
          virsh dominfo "$VM_NAME" 2>/dev/null || echo "  $VM_NAME: not created"
          echo ""
          echo "── Network interfaces ──"
          virsh domiflist "$VM_NAME" 2>/dev/null || echo "  no interfaces (VM not created)"
          echo ""
          echo "── DHCP leases (virbr0) ──"
          virsh net-dhcp-leases default 2>/dev/null || echo "  no leases"
          echo ""
          echo "── Browser access ──"
          echo "  http://localhost:${toString novncPort}/vnc.html"
          echo ""
          echo "── noVNC service ──"
          systemctl is-active novnc 2>/dev/null || echo "  novnc: not running"
        '')

        # Delete the VM + its disk
        (pkgs.writeShellScriptBin "tsbw-vm-nuke" ''
          set -euo pipefail
          VM_NAME="tsbw-win"
          virsh destroy "$VM_NAME" 2>/dev/null || true
          virsh undefine "$VM_NAME" --remove-all-storage 2>/dev/null || true
          echo "VM $VM_NAME destroyed and disk removed."
        '')
      ];

      # ── Domain-join PowerShell script ──────────────────────────────────
      # Available at /etc/tsbw-vm/domain-join.ps1 — copy into the VM and run
      # as admin to join ausbildung.tsbw.de.  Unlike the lab script, this one
      # uses DHCP-provided DNS (the TSBW DNS servers already resolve
      # ausbildung.tsbw.de), so no hardcoded DC IP.
      environment.etc."tsbw-vm/domain-join.ps1".text = ''
        # Join the ausbildung.tsbw.de AD domain.
        # Usage (from within the VM, as admin):
        #   .\domain-join.ps1
        #   .\domain-join.ps1 -Domain "ausbildung.tsbw.de" -OU "OU=Workstations,DC=ausbildung,DC=tsbw,DC=de"

        param(
          [string]$Domain = "ausbildung.tsbw.de",
          [string]$OU
        )

        # DNS is already set by DHCP (TSBW DNS servers resolve ausbildung.tsbw.de).
        # Verify we can resolve the domain
        try {
          Resolve-DnsName -Name "_ldap._tcp.$Domain" -Type SRV -ErrorAction Stop | Out-Null
        } catch {
          Write-Error "Cannot resolve _ldap._tcp.$Domain — check DNS settings."
          Write-Host "Current DNS servers:"
          Get-DnsClientServerAddress | Format-Table -AutoSize
          exit 1
        }

        Write-Host "Joining domain $Domain..."
        if ($OU) {
          Add-Computer -DomainName $Domain -OUPath $OU -Credential (Get-Credential) -Restart -Force
        } else {
          Add-Computer -DomainName $Domain -Credential (Get-Credential) -Restart -Force
        }

        Write-Host "Joined domain $Domain. VM will restart."
      '';

      # ── Bridge network for the VM ──────────────────────────────────────
      # libvirt's default network (virbr0) provides NAT for the initial
      # Windows install.  After install, tsbw-vm-bridge hot-adds a macvtap
      # NIC on enp1s0 so the VM gets a real TSBW IP and can reach the AD.
      # The default network is enabled by nixpkgs when libvirtd is enabled.
    }
  ;
}
