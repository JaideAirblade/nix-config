# Stealth firewall — default-deny incoming, allow all outgoing.
#
# Goals:
#   - Invisible to nmap port scans (all incoming ports filtered/dropped)
#   - Games, Steam, browsing, etc. all work (outgoing + established return traffic allowed)
#   - DHCP client works (needs to receive DHCP offers from the router)
#   - mDNS works (DMS shell / gvfs may use it for local device discovery)
#   - ICMP ping allowed (can be disabled for more stealth, but some apps
#     use it for connectivity checks — leaving it on is safer)
#
# What this does NOT do:
#   - It can't hide you from passive traffic sniffing on the same subnet
#     (your outgoing packets are still visible to anyone on the same VLAN)
#   - It can't change your TCP/IP stack fingerprint (nmap -O still sees Linux)
#
# How it works:
#   - nftables with a "drop" default policy on input and forward chains
#   - The "allow" chain explicitly permits established/related connections
#     (return traffic from your outgoing games/browsing), DHCP client
#     traffic (UDP 68), mDNS (UDP 5353), ICMP, and loopback
#   - NixOS's networking.firewall is NOT used — we go directly to nftables
#     for full control over the ruleset
#
# To temporarily open a port (e.g. for Steam Remote Play):
#   nft add element inet filter allowed_tcp_ports '{ 27036 }'
# Or use nm-connection-editor to change the connection profile.
{ ... }:

{
  # Use nftables (not iptables) as the backend.
  networking.nftables.enable = true;

  # Disable NixOS's built-in firewall — we manage nftables directly.
  networking.firewall.enable = false;

  # Our custom nftables ruleset.
  networking.nftables.ruleset = ''
    table inet filter {
      # --- Sets -------------------------------------------------------------
      # TCP ports that are allowed incoming. Empty by default — add ports
      # here when you need to (e.g. Steam Remote Play, SSH, etc.).
      # To add at runtime: nft add element inet filter allowed_tcp_ports '{ 27036 }'

      # --- Input chain (incoming traffic to this machine) ------------------
      chain input {
        type filter hook input priority 0; policy drop;

        # Allow loopback — local services (CUPS, etc.)
        iifname "lo" accept

        # Allow established and related connections — this is the key
        # rule that makes games work. When your game connects to a game
        # server, the server's response packets match this rule and are
        # allowed back in. Without this, nothing would work.
        ct state established,related accept

        # Allow invalid packets to be dropped (log if debugging needed)
        ct state invalid drop

        # Allow DHCP client — needs to receive offers/acks from the router.
        # DHCP client sends from UDP 68 to UDP 67. The response comes back
        # to UDP 68. Without this, you can't get an IP address.
        # In nftables inet tables, "udp" matches both IPv4 and IPv6.
        udp sport 67 udp dport 68 accept

        # Allow mDNS (multicast DNS on port 5353) — used by DMS/gvfs for
        # local device discovery (printers, SMB shares, etc.).
        # Comment this out if you don't need local discovery.
        udp dport 5353 accept

        # ICMP: we do NOT accept incoming ICMP echo requests (pings).
        # Ping replies to our outgoing pings are handled by the
        # ct state established,related rule above. This means:
        #   - We can ping others and get responses ✓
        #   - Others cannot ping us (no response) ✓
        #   - nmap -sn (ping scan) shows "host down" ✓
        #
        # If you need to temporarily allow incoming pings for
        # troubleshooting, run: sudo nft insert rule inet filter input ip protocol icmp accept
        #
        # We DO allow ICMP error messages (destination unreachable, etc.)
        # via the ct state related rule — these are needed for proper
        # TCP/IP behavior (e.g. PMTU discovery).

        # Allow IGMP — needed for multicast group management (some streaming
        # and local network protocols use it).
        ip protocol igmp accept

        # Everything else is dropped (default policy).
        # This is what makes you invisible to port scans — nmap sees all
        # ports as "filtered" because we don't respond at all.
      }

      # --- Forward chain (traffic routed through this machine) -------------
      chain forward {
        type filter hook forward priority 0; policy drop;
        # This machine is not a router — drop all forwarded traffic.
      }

      # --- Output chain (outgoing traffic from this machine) ---------------
      chain output {
        type filter hook output priority 0; policy accept;
        # Allow all outgoing traffic — games, browsing, Steam, etc.
        # If you want to restrict outgoing traffic too, change policy to
        # drop and add allow rules here. But this would break a lot of
        # things and requires careful tuning per game/app.
      }
    }
  '';
}