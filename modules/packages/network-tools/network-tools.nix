{ pkgs, ... }:

{
  programs.wireshark.enable = true;

  environment.systemPackages = with pkgs; [
    # --- Discovery & scanning ---
    nmap           # Network discovery & security auditing (includes ncat)
    arp-scan       # ARP scanning & fingerprinting — find devices by MAC
    fping          # Fast parallel ICMP ping for subnet sweeps
    masscan        # Fast port scanning of large networks

    # --- Tracing & path diagnostics ---
    mtr            # Combined traceroute + ping (real-time path diagnostics)
    traceroute     # Classic route tracing
    arping         # ARP-level ping — find devices that don't respond to ICMP
    p0f            # Passive OS fingerprinting from network traffic

    # --- Packet capture & analysis ---
    tcpdump        # Command-line packet sniffer
    termshark      # TUI for tshark (Wireshark in terminal)
    tshark         # CLI Wireshark — deep protocol analysis
    tcpflow        # Extract TCP streams from captured traffic
    ngrep          # Grep for network traffic — search packets by payload
    wireshark      # GUI (qt) — capture via the wireshark group setcap wrapper

    # --- Bandwidth & performance ---
    iperf3         # Bandwidth testing between hosts
    nload          # Real-time bandwidth monitor (ncurses)
    iftop          # Per-connection bandwidth display

    # --- DNS diagnostics ---
    bind           # provides dig, nslookup, named-checkzone, etc.
    dnsutils       # provides dig, nslookup, delv, nsupdate

    # --- Low-level network utilities ---
    netcat         # TCP/UDP Swiss army knife — port scanning, banner grabbing, debugging
    socat          # Bidirectional data relay between channels (TCP, UDP, Unix sockets, files)
    ethtool        # Query/control network driver & hardware (link speed, duplex, WoL)
    bridge-utils   # Configure Linux bridges
    vlan           # VLAN configuration tools (802.1Q)
    conntrack-tools # Track connection state tables (conntrack -L, -D)
    nftables       # nft firewall — inspect rules, debug packet flow

    # --- IP & MAC manipulation ---
    ipcalc         # IP subnet calculator — CIDR, broadcast, network range
    macchanger     # View/spoof MAC addresses
    arpoison       # Inject ARP replies — for testing ARP cache poisoning

    # --- Serial & console ---
    minicom        # Serial terminal — configure switches/routers via console cable

    # --- Process namespace debugging ---
    util-linux     # provides nsenter, unshare — enter network namespaces for debugging

    # --- WHOIS ---
    whois          # WHOIS lookups for IP/ASN/domain ownership

    ivpn-ui
  ];
}