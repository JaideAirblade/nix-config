# Luna-Server host-specific networking — sets the hostname.
# The shared modules/network/network.nix handles NetworkManager.
#
# Interfaces (from the live ISO):
#   eno1 / enp195s0  — Aquantia AQC113 10Gbase-T (primary, wired to the LAN)
#   wlp194s0         — Intel AX200 WiFi
# UwU's SEBNS quickack route and Realtek EEE workaround are NOT carried over:
# this box has different NICs and no such requirements yet.
#
# --- WiFi regulatory domain ---------------------------------------------
# Without this, /sys/module/cfg80211/parameters/ieee80211_regdom stays "00"
# (DFS-UNSET / world) after every boot, and `iw reg get` reports the global
# default as country 00. The Intel AX200 firmware overrides this for itself
# (phy0 reports country DE) so the radio still works, but kernel-level queries
# and tools like `iw`/crda behave inconsistently. Setting the kernel
# parameter at boot restores DE everywhere.
#   Reference: https://wireless.wiki.kernel.org/en/developers/Regulatory
# --- Intel AX200 BT coexistence ------------------------------------------
# This server has no BT peripherals, but bluez must stay enabled (see
# CHANGELOG 2026-08-14). With bt_coex_active=Y (default), the iwlwifi
# firmware time-shares antenna chains with the BT radio even when BT is
# idle/down: chain 1 WiFi RX drops ~10 dB (firmware ignores the chain
# during BT slots), RX collapses to NSS 1 / 6.5-57 Mbit/s under load
# while TX holds 520 Mbit/s NSS 2, plus periodic 100-400 ms latency
# spikes and up to 6% packet loss to the gateway.
# bt_coex_active=0 tells the firmware to keep both chains on WiFi.
# Needs a reboot (module param is read-only at runtime); do NOT set it
# by reloading iwlwifi live — that re-triggers the AX200
# "session protection is over already" association bug.
_: {
  nixos.hosts."Luna-Server" =
    _:

    {
      networking.hostName = "Luna-Server"; # must match the nixosConfigurations key in flake.nix

      boot.kernelParams = [ "cfg80211.ieee80211_regdom=DE" ];

      # WiFi fix 2026-08-14 — see hosts/Luna-Server/CHANGELOG.md
      boot.extraModprobeConfig = ''
        options iwlwifi bt_coex_active=0
      '';
    }
  ;
}
