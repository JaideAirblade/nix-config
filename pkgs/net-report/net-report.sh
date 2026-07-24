#!/usr/bin/env bash
# net-report — comprehensive network status report
#
# Collects everything: LLDP neighbors, interfaces, routes, DNS, sockets,
# firewall, WiFi, ethtool, ARP, conntrack, public IP, traceroute, and more.
# Presents it with semantic colors, formatted tables, and a visual summary.
#
# Usage:
#   net-report                  — full report to stdout
#   net-report --json           — machine-readable JSON
#   net-report --section <name> — print only one section (see --list-sections)
#   net-report --verbose         — show full command output (no truncation/parsing)
#   net-report --no-trace       — skip traceroute/mtr (faster, no network probes)
#   net-report --no-public      — skip public IP lookup (no outbound HTTP)
#   net-report --no-ping        — skip connectivity tests
#   net-report --no-color       — disable colors (also auto-disabled if not a TTY)
#   net-report --list-sections  — list available sections
#   net-report --help, -h       — show help
#
# Requires: ip, ss, nmcli, nft, ethtool, dig, resolvectl, lldpctl,
#           traceroute/mtr, curl, bridge, rfkill, hostname, conntrack, ping,
#           column, awk, sed
# Optional: iw (for raw WiFi radio info), nmap (for local network scan)
#
# Written for Jaide's NixOS — installed via pkgs/net-report in ~/nixos.

set -euo pipefail

# ---------------------------------------------------------------------------
# Config & defaults
# ---------------------------------------------------------------------------
SCRIPT_NAME="$(basename "$0")"
TRACE=yes
PUBLIC=yes
PING=yes
JSON=no
VERBOSE=no
COMPACT=no
SECTION=""
USE_COLOR=yes

# All available sections (in display order)
SECTIONS=(
    summary
    host-identity
    connectivity
    lldp
    switch-info
    interfaces
    ethtool
    wifi
    wifi-scan
    routes
    dns
    neighbors
    sockets
    conntrack
    firewall
    firewall-analysis
    nm
    vpn
    rfkill
    bridge
    multicast
    discovery
    sysctl
    kernel
    public
    trace
)

# Compact mode: only show these sections (the most useful ones)
COMPACT_SECTIONS=(
    summary
    host-identity
    connectivity
    lldp
    switch-info
    interfaces
    routes
    dns
    sockets
    vpn
    discovery
    public
)

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------
usage() {
    cat <<EOF
$SCRIPT_NAME — comprehensive network status report

Usage: $SCRIPT_NAME [OPTIONS]

Options:
  --json             Output JSON (best effort, mixed with raw text in fields)
  --section <name>   Print only the named section (use --list-sections to see names)
  --verbose           Show full command output (no truncation/parsing)
  --no-trace         Skip traceroute/mtr section
  --no-public        Skip public IP lookup
  --no-ping          Skip connectivity tests (ping)
  --no-color         Disable colors (also auto-disabled if not a TTY)
  --compact          Show only key sections (summary, connectivity, LLDP,
                     switch-info, interfaces, routes, DNS, sockets, VPN,
                     discovery, public IP) — skips verbose sections
  --list-sections    List available section names and exit
  --help, -h         Show this help

Sections:
$(printf '  %s\n' "${SECTIONS[@]}")
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --json)        JSON=yes; shift ;;
        --section)    SECTION="$2"; shift 2 ;;
        --verbose)    VERBOSE=yes; shift ;;
        --no-trace)   TRACE=no; shift ;;
        --no-public)  PUBLIC=no; shift ;;
        --no-ping)    PING=no; shift ;;
        --no-color)   USE_COLOR=no; shift ;;
        --compact)    COMPACT=yes; shift ;;
        --list-sections) printf '%s\n' "${SECTIONS[@]}"; exit 0 ;;
        --help|-h)    usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Color setup
# ---------------------------------------------------------------------------
# Disable colors if: --no-color, NO_COLOR env var, JSON mode, or not a TTY
if [[ "$USE_COLOR" == "no" ]] || [[ -n "${NO_COLOR:-}" ]] || [[ "$JSON" == "yes" ]] || [[ ! -t 1 ]]; then
    R='' B='' DIM='' CY='' GR='' YE='' MG='' BL='' RD='' BR='' BOLD=''
    OK='✓' FAIL='✗' WARN='⚠' INFO='ℹ'
else
    R='\033[0m'    B='\033[1m'   DIM='\033[2m'
    CY='\033[36m'  GR='\033[32m'  YE='\033[33m'
    MG='\033[35m'  BL='\033[34m'  RD='\033[31m'  BR='\033[90m'
    BOLD='\033[1m'
    OK='✓' FAIL='✗' WARN='⚠' INFO='ℹ'
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Print a section header
header() {
    local title="$1"
    echo ""
    echo -e "${B}${CY}┌──────────────────────────────────────────────────────────────┐${R}"
    echo -e "${B}${CY}│ ${title}$(printf '%*s' $((61 - ${#title})) '') │${R}"
    echo -e "${B}${CY}└──────────────────────────────────────────────────────────────┘${R}"
}

# Run a command, show output. If it fails, note it but don't crash.
run() {
    local label="$1"; shift
    echo -e "${DIM}# ${label}${R}"
    "$@" 2>&1 || echo -e "${RD}(failed)${R}"
    echo ""
}

# Run a command silently (suppress "failed" for commands that may be absent)
run_silent() {
    local label="$1"; shift
    echo -e "${DIM}# ${label}${R}"
    "$@" 2>/dev/null || true
    echo ""
}

# Check if we should run a given section
should_run() {
    [[ -z "$SECTION" || "$SECTION" == "$1" ]]
}

# Get physical interfaces (exclude lo, docker, br-*, veth*, virbr*, tun*, tap*)
physical_ifaces() {
    ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | \
        grep -vE '^(lo|docker|br-|veth|virbr|tun|tap|wg|ivpn)' || true
}

# Format bytes as human-readable
human_bytes() {
    local bytes=$1
    if [[ $bytes -ge 1073741824 ]]; then
        awk "BEGIN{printf \"%.1f GB\", $bytes/1073741824}"
    elif [[ $bytes -ge 1048576 ]]; then
        awk "BEGIN{printf \"%.1f MB\", $bytes/1048576}"
    elif [[ $bytes -ge 1024 ]]; then
        awk "BEGIN{printf \"%.1f KB\", $bytes/1024}"
    else
        echo "$bytes B"
    fi
}

# Color a status word (UP=green, DOWN=red, etc.)
color_status() {
    local status="$1"
    case "$status" in
        UP|connected|full|reachable|ESTABLISHED|REACHABLE|on|yes) echo -e "${GR}${status}${R}" ;;
        DOWN|disconnected|none|unreachable|failed|off|no) echo -e "${RD}${status}${R}" ;;
        WARNING|warn|STALE|DELAY) echo -e "${YE}${status}${R}" ;;
        *) echo -e "${BR}${status}${R}" ;;
    esac
}

# Color a check/cross result
color_check() {
    local ok=$1; shift
    local msg="$*"
    if [[ "$ok" == "yes" ]]; then
        echo -e "  ${GR}${OK}${R}  ${msg}"
    else
        echo -e "  ${RD}${FAIL}${R}  ${msg}"
    fi
}

# Print a table from piped input using column -t
print_table() {
    column -t -s $'\t' 2>/dev/null || cat
}

# Truncate a string to N chars with ellipsis
truncate_str() {
    local str="$1" max="$2"
    if [[ ${#str} -gt $max ]]; then
        echo "${str:0:$((max-3))}..."
    else
        echo "$str"
    fi
}

# Spinner for slow operations (runs in background)
SPINNER_PID=""
SPINNER_MSG=""
start_spinner() {
    [[ ! -t 1 || "$USE_COLOR" == "no" ]] && return
    SPINNER_MSG="$1"
    (
        local chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
        while true; do
            for ((i=0; i<${#chars}; i++)); do
                printf "\r${DIM}%s %s...${R}" "${chars:$i:1}" "$SPINNER_MSG"
                sleep 0.08
            done
        done
    ) &
    SPINNER_PID=$!
}

stop_spinner() {
    [[ -z "$SPINNER_PID" ]] && return
    kill "$SPINNER_PID" 2>/dev/null || true
    wait "$SPINNER_PID" 2>/dev/null || true
    SPINNER_PID=""
    printf '\r\033[K'
}

# ---------------------------------------------------------------------------
# Sections
# ---------------------------------------------------------------------------

# --- Summary card (fastfetch-style at-a-glance) ---------------------------
section_summary() {
    header "NETWORK SUMMARY"

    local hostname_str default_gw default_iface nm_state nm_conn
    hostname_str=$(hostname 2>/dev/null || echo "?")
    default_gw=$(ip -4 route show default 2>/dev/null | awk '{print $3; exit}' || echo "none")
    default_iface=$(ip -4 route show default 2>/dev/null | awk '{print $5; exit}' || echo "?")
    nm_state=$(nmcli -t -f STATE general status 2>/dev/null || echo "unknown")
    nm_conn=$(nmcli -t -f CONNECTIVITY general status 2>/dev/null || echo "unknown")

    # Count interfaces
    local total_ifaces up_ifaces
    total_ifaces=$(ip -o link show 2>/dev/null | wc -l || echo "0")
    up_ifaces=$(ip -o link show 2>/dev/null | grep -c 'state UP' || echo "0")

    # Count sockets
    local tcp_estab tcp_listen udp_listen
    tcp_estab=$( (ss -tnH state established 2>/dev/null || true) | grep -c . || true)
    [[ -z "$tcp_estab" ]] && tcp_estab=0
    tcp_listen=$( (ss -tlnH 2>/dev/null || true) | grep -c . || true)
    [[ -z "$tcp_listen" ]] && tcp_listen=0
    udp_listen=$( (ss -ulnH 2>/dev/null || true) | grep -c . || true)
    [[ -z "$udp_listen" ]] && udp_listen=0

    # VPN status
    local vpn_status
    if command -v ivpn &>/dev/null; then
        vpn_status=$( (ivpn status 2>/dev/null || true) | head -1 | awk -F: '{gsub(/^ +| +$/,"",$2); print $2}' || true)
        [[ -z "$vpn_status" ]] && vpn_status="Unknown"
    else
        vpn_status="(no VPN tool)"
    fi

    # Conntrack info
    local ct_count ct_max
    ct_count=$( (conntrack -L 2>/dev/null || true) | grep -c . || true)
    [[ -z "$ct_count" ]] && ct_count=0
    ct_max=$(cat /proc/sys/net/nf_conntrack_max 2>/dev/null || echo "?")

    # RFkill
    local rfkill_status
    if command -v rfkill &>/dev/null; then
        if rfkill list 2>/dev/null | grep -q 'blocked: yes'; then
            rfkill_status="blocked"
        else
            rfkill_status="clear"
        fi
    else
        rfkill_status="?"
    fi

    # Public IP (if not skipped)
    local pub_ip="(skipped)"
    if [[ "$PUBLIC" == "yes" ]]; then
        pub_ip=$( (curl -s4 --max-time 5 https://ifconfig.me 2>/dev/null || true) )
        [[ -z "$pub_ip" ]] && pub_ip="(unreachable)"
    fi

    # Print the card
    echo -e "${B}${MG}╔═══════════════════════════════════════════════════════════╗${R}"
    local card_line="Network Status Report — $(date '+%Y-%m-%d %H:%M:%S')"
    local pad_len=$((60 - ${#card_line}))
    [[ $pad_len -lt 0 ]] && pad_len=0
    echo -e "${B}${MG}║${R} ${BOLD}${card_line}${R}$(printf '%*s' "$pad_len" '') ${B}${MG}║${R}"

    # Helper for summary lines
    _sum_line() {
        local label="$1" val="$2"
        printf "  ${B}%-18s${R} %s\n" "$label" "$val"
    }

    echo -e "${B}${MG}║${R}                                                            ${B}${MG}║${R}"
    _sum_line "Hostname:" "$hostname_str"
    _sum_line "NM State:" "$(color_status "$nm_state")"
    _sum_line "Connectivity:" "$(color_status "$nm_conn")"
    _sum_line "Default GW:" "${default_gw:-none} via ${default_iface}"
    _sum_line "Public IP:" "$pub_ip"
    _sum_line "VPN:" "$(color_status "${vpn_status:-Unknown}")"
    _sum_line "Interfaces:" "${up_ifaces} up / ${total_ifaces} total"
    _sum_line "TCP estab:" "${tcp_estab} connections"
    _sum_line "TCP listen:" "${tcp_listen} ports"
    _sum_line "UDP listen:" "${udp_listen} ports"
    _sum_line "Conntrack:" "${ct_count}/${ct_max} entries"
    _sum_line "RFKill:" "$(color_status "$rfkill_status")"
    echo -e "${B}${MG}╚═══════════════════════════════════════════════════════════╝${R}"

    # Interface quick-table
    echo ""
    echo -e "  ${B}Interface Quick Status:${R}"
    printf "  %-14s %-8s %-10s %-22s %s\n" "INTERFACE" "STATE" "SPEED" "IP ADDRESS" "MAC"
    printf "  %-14s %-8s %-10s %-22s %s\n" "---------" "-----" "-----" "----------" "---"
    while read -r iface; do
        [[ "$iface" == "lo" ]] && continue
        local state ip_addr mac speed
        state=$(ip -o link show "$iface" 2>/dev/null | grep -oP 'state \K\w+' || echo "?")
        ip_addr=$(ip -4 -br addr show "$iface" 2>/dev/null | awk '{print $3}' || echo "")
        mac=$(ip -o link show "$iface" 2>/dev/null | awk -F'link/ether ' '{print $2}' | awk '{print $1}' || echo "")
        speed=$(ethtool "$iface" 2>/dev/null | grep -oP 'Speed: \K.*' || echo "?")
        [[ -z "$ip_addr" ]] && ip_addr="-"
        [[ -z "$mac" ]] && mac="-"
        [[ -z "$speed" ]] && speed="?"
        printf "  %-14s %-8s %-10s %-22s %s\n" "$iface" "$(color_status "$state")" "$speed" "$ip_addr" "$mac"
    done < <(ip -o link show 2>/dev/null | awk -F': ' '{print $2}')
}

# --- Connectivity (ping tests) ---------------------------------------------
section_connectivity() {
    header "CONNECTIVITY TEST"
    if [[ "$PING" != "yes" ]]; then
        echo "  (skipped — --no-ping)"
        return
    fi

    local default_gw
    default_gw=$(ip -4 route show default 2>/dev/null | awk '{print $3; exit}' || echo "")

    # Test 1: ping gateway
    if [[ -n "$default_gw" ]]; then
        local gw_out gw_ok gw_ms
        gw_out=$( (ping -c 3 -W 2 -q "$default_gw" 2>/dev/null || true) )
        if echo "$gw_out" | grep -q 'rtt min'; then
            gw_ok=yes
            gw_ms=$(echo "$gw_out" | grep -oP 'rtt min/avg/max/mdev = [\d.]+/[\d.]+/[\d.]+/[\d.]+' | awk -F'/' '{printf "%.1f", $5}')
        else
            gw_ok=no; gw_ms="?"
        fi
        if [[ "$gw_ok" == "yes" ]]; then
            color_check yes "Gateway $default_gw reachable (${gw_ms}ms avg)"
        else
            color_check no "Gateway $default_gw UNREACHABLE"
        fi
    else
        echo -e "  ${DIM}No default gateway configured${R}"
    fi

    # Test 2: ping internet (1.1.1.1)
    local inet_out inet_ok inet_ms
    inet_out=$( (ping -c 3 -W 2 -q 1.1.1.1 2>/dev/null || true) )
    if echo "$inet_out" | grep -q 'rtt min'; then
        inet_ok=yes
        inet_ms=$(echo "$inet_out" | grep -oP 'rtt min/avg/max/mdev = [\d.]+/[\d.]+/[\d.]+/[\d.]+' | awk -F'/' '{printf "%.1f", $5}')
    else
        inet_ok=no; inet_ms="?"
    fi
    if [[ "$inet_ok" == "yes" ]]; then
        color_check yes "Internet 1.1.1.1 reachable (${inet_ms}ms avg)"
    else
        color_check no "Internet 1.1.1.1 UNREACHABLE"
    fi

    # Test 3: DNS resolution test
    local dns_ok dns_ip
    dns_ip=$(dig +short +time=3 +tries=1 A example.com 2>/dev/null | head -1 || echo "")
    if [[ -n "$dns_ip" ]]; then
        color_check yes "DNS resolves example.com → $dns_ip"
    else
        color_check no "DNS resolution FAILED"
    fi

    # Test 4: HTTP connectivity (HTTP 204 check)
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://connectivity-check.ubuntu.com 2>/dev/null || echo "000")
    if [[ "$http_code" == "204" ]]; then
        color_check yes "HTTP connectivity check passed (204)"
    else
        color_check no "HTTP connectivity check failed (HTTP $http_code)"
    fi
}

# --- LLDP / CDP neighbors --------------------------------------------------
section_lldp() {
    header "LLDP / CDP NEIGHBORS"
    if ! command -v lldpctl &>/dev/null; then
        echo -e "  ${RD}lldpctl not found${R} — install lldpd"
        return
    fi

    if [[ "$VERBOSE" == "yes" ]]; then
        run "LLDP neighbors (full)" lldpctl
        run "LLDP neighbors (JSON)" lldpctl -f json
        return
    fi

    # Parsed summary table
    local lldp_out
    lldp_out=$( (lldpctl 2>/dev/null || true) )
    # Check for empty output or "No LLDP neighbors" using bash builtins (no grep dependency)
    if [[ -z "$lldp_out" ]] || [[ "$lldp_out" == *"No LLDP neighbors"* ]]; then
        echo -e "  ${DIM}No LLDP neighbors discovered${R}"
        return
    fi

    printf "  %-14s %-20s %-15s %-15s %-15s %s\n" "INTERFACE" "SWITCH" "CHASSIS ID" "PORT" "MGMT IP" "CAPABILITIES"
    printf "  %-14s %-20s %-15s %-15s %-15s %s\n" "---------" "------" "----------" "----" "-------" "------------"

    # Parse lldpctl output — sections separated by "Interface:" lines
    local cur_iface="" cur_switch="" cur_chassis="" cur_port="" cur_mgmt="" cur_caps=""
    while IFS= read -r line; do
        if [[ "$line" =~ ^Interface: ]]; then
            # Print previous entry
            if [[ -n "$cur_iface" ]]; then
                printf "  %-14s %-20s %-15s %-15s %-15s %s\n" \
                    "$(truncate_str "$cur_iface" 14)" \
                    "$(truncate_str "$cur_switch" 20)" \
                    "$(truncate_str "$cur_chassis" 15)" \
                    "$(truncate_str "$cur_port" 15)" \
                    "$(truncate_str "$cur_mgmt" 15)" \
                    "$(truncate_str "$cur_caps" 30)"
            fi
            cur_iface=$(echo "$line" | awk -F',' '{print $1}' | awk '{print $2}')
            cur_switch="" cur_chassis="" cur_port="" cur_mgmt="" cur_caps=""
        elif [[ "$line" =~ ^[[:space:]]+ChassisID: ]]; then
            cur_chassis=$(echo "$line" | awk '{print $2, $3}' | sed 's/mac //')
        elif [[ "$line" =~ ^[[:space:]]+SysName: ]]; then
            cur_switch=$(echo "$line" | awk '{$1=$1; print}' | sed 's/^SysName:[[:space:]]*//')
        elif [[ "$line" =~ ^[[:space:]]+MgmtIP: ]]; then
            cur_mgmt=$(echo "$line" | awk '{print $2}')
        elif [[ "$line" =~ ^[[:space:]]+PortID: ]]; then
            cur_port=$(echo "$line" | awk '{print $2, $3}' | sed 's/mac //')
        elif [[ "$line" =~ ^[[:space:]]+PortDescr: ]]; then
            cur_port="$cur_port($(echo "$line" | awk '{$1=$1; print}' | sed 's/^PortDescr:[[:space:]]*//'))"
        elif [[ "$line" =~ ^[[:space:]]+Capability: ]]; then
            local cap
            cap=$(echo "$line" | awk '{print $2}' | sed 's/,//')
            [[ -n "$cap" ]] && cur_caps="${cur_caps}${cap} "
        fi
    done <<< "$lldp_out"

    # Print last entry
    if [[ -n "$cur_iface" ]]; then
        printf "  %-14s %-20s %-15s %-15s %-15s %s\n" \
            "$(truncate_str "$cur_iface" 14)" \
            "$(truncate_str "$cur_switch" 20)" \
            "$(truncate_str "$cur_chassis" 15)" \
            "$(truncate_str "$cur_port" 15)" \
            "$(truncate_str "$cur_mgmt" 15)" \
            "$(truncate_str "$cur_caps" 30)"
    fi

    echo ""
    if [[ "$VERBOSE" == "yes" ]]; then
        run "Raw lldpctl output" lldpctl
    fi
}

# --- Interfaces (parsed, human-readable) ----------------------------------
section_interfaces() {
    header "INTERFACES"

    if [[ "$VERBOSE" == "yes" ]]; then
        run "All links (detailed)" ip -d link show
        run "All addresses (detailed)" ip addr show
        run "Interface statistics" ip -s link show
        return
    fi

    # Parsed interface table with human-readable stats
    echo -e "  ${B}Interface Details:${R}"
    echo ""

    while read -r iface; do
        local state mtu mac ip4 ip6 qlen driver permaddr
        state=$(ip -o link show "$iface" 2>/dev/null | grep -oP 'state \K\w+' || echo "?")
        mtu=$(ip -o link show "$iface" 2>/dev/null | grep -oP 'mtu \K\d+' || echo "?")
        mac=$(ip -o link show "$iface" 2>/dev/null | awk -F'link/ether ' '{print $2}' | awk '{print $1}' || echo "-")
        permaddr=$(ethtool -P "$iface" 2>/dev/null | grep -oP 'Permanent address: \K.*' || echo "")
        ip4=$(ip -4 -br addr show "$iface" 2>/dev/null | awk '{print $3}' || echo "-")
        ip6=$(ip -6 -br addr show "$iface" 2>/dev/null | awk '{print $3}' | head -1 || echo "-")
        qlen=$(ip -o link show "$iface" 2>/dev/null | grep -oP 'qlen \K\d+' || echo "-")

        # Stats
        local rx_bytes rx_packets rx_errs rx_drops tx_bytes tx_packets tx_errs tx_drops
        read -r rx_bytes rx_packets rx_errs rx_drops _ < <(ip -s link show "$iface" 2>/dev/null | awk '/RX:/{getline; print}' || echo "0 0 0 0 0")
        read -r tx_bytes tx_packets tx_errs tx_drops _ < <(ip -s link show "$iface" 2>/dev/null | awk '/TX:/{getline; print}' || echo "0 0 0 0 0")

        # Format
        [[ -z "$ip4" ]] && ip4="-"
        [[ -z "$ip6" ]] && ip6="-"
        [[ -z "$mac" ]] && mac="-"

        echo -e "  ${B}${iface}${R} — state: $(color_status "$state"), MTU: $mtu, qlen: $qlen"
        echo -e "    MAC: ${mac}$([[ -n "$permaddr" && "$permaddr" != "$mac" ]] && echo -e " ${DIM}(perm: ${permaddr})${R}")"
        echo -e "    IPv4: ${ip4}"
        echo -e "    IPv6: ${ip6}"
        echo -e "    RX:   $(human_bytes "${rx_bytes:-0}") in ${rx_packets:-0} pkts" \
            "$([[ "${rx_errs:-0}" -gt 0 ]] && echo -e "${RD}(${rx_errs} errs)${R}" || echo "")" \
            "$([[ "${rx_drops:-0}" -gt 0 ]] && echo -e "${YE}(${rx_drops} drops)${R}" || echo "")"
        echo -e "    TX:   $(human_bytes "${tx_bytes:-0}") in ${tx_packets:-0} pkts" \
            "$([[ "${tx_errs:-0}" -gt 0 ]] && echo -e "${RD}(${tx_errs} errs)${R}" || echo "")" \
            "$([[ "${tx_drops:-0}" -gt 0 ]] && echo -e "${YE}(${tx_drops} drops)${R}" || echo "")"

        # VLAN info
        local vlan=""
        vlan=$(ip -d link show "$iface" 2>/dev/null | grep -oP 'vlan protocol \S+ id \K\d+' || true)
        [[ -n "$vlan" ]] && echo -e "    ${BL}VLAN:${R} $vlan"

        echo ""
    done < <(ip -o link show 2>/dev/null | awk -F': ' '{print $2}')
}

# --- WiFi (parsed with signal bars) ---------------------------------------
section_wifi() {
    header "WIFI"
    if [[ "$VERBOSE" == "yes" ]]; then
        run "NM WiFi devices" nmcli -f all device status 2>/dev/null || true
        run "NM WiFi list (scan results)" nmcli -f SSID,BSSID,MODE,CHAN,FREQ,SIGNAL,SECURITY,BARS dev wifi list 2>/dev/null || true
        if command -v iw &>/dev/null; then
            for iface in $(iw dev 2>/dev/null | awk '/Interface/{print $2}'); do
                run "iw dev $iface info" iw dev "$iface" info
                run "iw dev $iface link" iw dev "$iface" link
            done
        fi
        return
    fi

    # WiFi device status
    echo -e "  ${B}WiFi Devices:${R}"
    nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device status 2>/dev/null | grep -i wifi | while IFS=: read -r dev type state conn; do
        printf "    %-12s %-10s %s\n" "$dev" "$(color_status "$state")" "$conn"
    done
    echo ""

    # Connected network details
    echo -e "  ${B}Connected Network:${R}"
    local ssid signal freq chan security
    ssid=$(nmcli -t -f ACTIVE,SSID,SIGNAL,FREQ,CHAN,SECURITY dev wifi list 2>/dev/null | grep '^yes:' | cut -d: -f2 || echo "")
    if [[ -n "$ssid" ]]; then
        signal=$(nmcli -t -f ACTIVE,SSID,SIGNAL,FREQ,CHAN,SECURITY dev wifi list 2>/dev/null | grep '^yes:' | cut -d: -f3)
        freq=$(nmcli -t -f ACTIVE,SSID,SIGNAL,FREQ,CHAN,SECURITY dev wifi list 2>/dev/null | grep '^yes:' | cut -d: -f4)
        chan=$(nmcli -t -f ACTIVE,SSID,SIGNAL,FREQ,CHAN,SECURITY dev wifi list 2>/dev/null | grep '^yes:' | cut -d: -f5)
        security=$(nmcli -t -f ACTIVE,SSID,SIGNAL,FREQ,CHAN,SECURITY dev wifi list 2>/dev/null | grep '^yes:' | cut -d: -f6)

        # Signal bars
        local bars=""
        if [[ -n "$signal" ]]; then
            if [[ $signal -ge 80 ]]; then bars="████"; elif [[ $signal -ge 60 ]]; then bars="███░"; elif [[ $signal -ge 40 ]]; then bars="██░░"; elif [[ $signal -ge 20 ]]; then bars="█░░░"; else bars="░░░░"; fi
        fi

        printf "    SSID:      %s\n" "$ssid"
        printf "    Signal:    %s (%s%%)\n" "$bars" "${signal:-?}"
        # freq from nmcli already includes "MHz" (e.g. "5180 MHz"), so don't add it again
        # Convert to GHz for readability if numeric MHz is present
        local freq_display="${freq:-?}"
        if [[ "$freq_display" =~ ^([0-9]+)\ MHz$ ]]; then
            local freq_mhz="${BASH_REMATCH[1]}"
            freq_display=$(awk "BEGIN{printf \"%.2f GHz\", ${freq_mhz}/1000}")
        fi
        printf "    Freq/Chan: %s / Ch %s\n" "$freq_display" "${chan:-?}"
        printf "    Security:  %s\n" "${security:-?}"
    else
        echo -e "    ${DIM}Not connected to any WiFi network${R}"
    fi
    echo ""

    # Scan results table
    echo -e "  ${B}Available Networks:${R}"
    printf "  %-30s %-8s %-6s %-10s %s\n" "SSID" "SIGNAL" "CHAN" "SECURITY" "BARS"
    printf "  %-30s %-8s %-6s %-10s %s\n" "-----------------------------" "------" "----" "----------" "----"
    nmcli -t -f SSID,SIGNAL,CHAN,SECURITY,BARS dev wifi list 2>/dev/null | while IFS=: read -r ssid signal chan sec bars; do
        [[ "$ssid" == "" ]] && ssid="(hidden)"
        local sig_color="$BR"
        if [[ -n "$signal" ]]; then
            if [[ $signal -ge 70 ]]; then sig_color="$GR"; elif [[ $signal -ge 50 ]]; then sig_color="$YE"; elif [[ $signal -ge 30 ]]; then sig_color="$RD"; fi
        fi
        printf "  %-30s ${sig_color}%-8s${R} %-6s %-10s %s\n" \
            "$(truncate_str "$ssid" 30)" "${signal:-?}" "${chan:-?}" "$sec" "$bars"
    done
}

# --- Ethtool (summary table + verbose option) ------------------------------
section_ethtool() {
    header "ETHTOOL (link details)"
    if [[ "$VERBOSE" == "yes" ]]; then
        for iface in $(physical_ifaces); do
            run "ethtool $iface" ethtool "$iface"
            run "ethtool $iface driver" ethtool -i "$iface" 2>/dev/null || true
            run "ethtool $iface statistics" ethtool -S "$iface" 2>/dev/null || true
            run "ethtool $iface ring params" ethtool -g "$iface" 2>/dev/null || true
            run "ethtool $iface coalescing" ethtool -c "$iface" 2>/dev/null || true
            run "ethtool $iface offload" ethtool -k "$iface" 2>/dev/null || true
        done
        return
    fi

    # Summary table
    printf "  %-14s %-12s %-8s %-10s %-8s %-12s %s\n" "INTERFACE" "DRIVER" "DUPLEX" "SPEED" "LINK" "AUTO-NEG" "FIRMWARE"
    printf "  %-14s %-12s %-8s %-10s %-8s %-12s %s\n" "---------" "-------" "------" "-----" "----" "--------" "--------"
    for iface in $(physical_ifaces); do
        local driver speed duplex link autoneg fw
        driver=$(ethtool -i "$iface" 2>/dev/null | grep -oP 'driver: \K.*' || echo "?")
        speed=$(ethtool "$iface" 2>/dev/null | grep -oP 'Speed: \K.*' || echo "?")
        duplex=$(ethtool "$iface" 2>/dev/null | grep -oP 'Duplex: \K.*' || echo "?")
        autoneg=$(ethtool "$iface" 2>/dev/null | grep -oP 'Auto-negotiation: \K.*' || echo "?")
        link="?"
        ethtool "$iface" 2>/dev/null | grep -q 'Link detected: yes' && link="yes" || link="no"
        fw=$(ethtool -i "$iface" 2>/dev/null | grep -oP 'firmware-version: \K.*' || echo "-")
        [[ -z "$fw" ]] && fw="-"

        # Detect WiFi interfaces: name starts with "wl" or driver is ath*/iwl*/mt76/brcm
        local is_wifi=no
        if [[ "$iface" == wl* ]]; then
            is_wifi=yes
        elif [[ -n "$driver" && "$driver" != "?" ]]; then
            case "$driver" in
                ath*|iwl*|mt76*|brcm*) is_wifi=yes ;;
            esac
        fi

        # WiFi interfaces (e.g. ath12k) don't support ethtool speed/duplex/link
        if [[ "$is_wifi" == "yes" ]]; then
            [[ "$speed" == "?" || -z "$speed" ]] && speed="N/A (WiFi)"
            [[ "$duplex" == "?" || -z "$duplex" ]] && duplex="N/A (WiFi)"
            [[ "$link" == "no" || "$link" == "?" ]] && link="N/A (WiFi)"
            [[ "$autoneg" == "?" || -z "$autoneg" ]] && autoneg="N/A (WiFi)"
        fi

        printf "  %-14s %-12s %-8s %-10s %-8s %-12s %s\n" \
            "$iface" "$driver" "$duplex" "$speed" "$(color_status "$link")" "$autoneg" "$(truncate_str "$fw" 20)"
    done

    # Per-interface offload summary
    echo ""
    echo -e "  ${B}Offload features (per interface):${R}"
    for iface in $(physical_ifaces); do
        echo -e "  ${B}$iface:${R}"
        ethtool -k "$iface" 2>/dev/null | grep -E '^(rx-checksumming|tx-checksumming|scatter-gather|tcp-segmentation|generic-segmentation|generic-receive-offload|large-receive-offload):' | while read -r line; do
            local key val
            key=$(echo "$line" | cut -d: -f1)
            val=$(echo "$line" | cut -d: -f2 | xargs)
            printf "    %-30s %s\n" "$key" "$(color_status "$val")"
        done || echo -e "    ${DIM}(ethtool not available for $iface)${R}"
    done
}

# --- WiFi scan (deauth + probe request sniffing) ---------------------------
# Sends deauth frames to force all connected devices to re-probe, then captures
# their probe requests to discover ALL WiFi devices on this network (not just
# those responding to ping). Requires root (monitor mode).
#
# This briefly disconnects all WiFi devices (1-3 seconds) — they reconnect
# automatically and most users won't notice the blip.
section_wifi-scan() {
    header "WIFI SCAN (deauth + probe sniff)"

    # Check if we have the needed capabilities (cap_net_admin + cap_net_raw)
    # These can be granted via security.wrappers in NixOS config, or via setcap
    # Check for wrapper binaries first (NixOS security.wrappers puts them in /run/wrappers/bin)
    local IW_BIN TCPDUMP_BIN AIREPLAY_BIN
    local has_admin=no has_raw=no
    if [[ -x /run/wrappers/bin/net-report-iw ]]; then
        IW_BIN=/run/wrappers/bin/net-report-iw
        has_admin=yes; has_raw=yes
    else
        IW_BIN=$(command -v iw 2>/dev/null || true)
    fi
    if [[ -x /run/wrappers/bin/net-report-tcpdump ]]; then
        TCPDUMP_BIN=/run/wrappers/bin/net-report-tcpdump
    else
        TCPDUMP_BIN=$(command -v tcpdump 2>/dev/null || true)
    fi
    if [[ -x /run/wrappers/bin/net-report-aireplay ]]; then
        AIREPLAY_BIN=/run/wrappers/bin/net-report-aireplay
    else
        AIREPLAY_BIN=$(command -v aireplay-ng 2>/dev/null || true)
    fi

    # Also check via capsh or root
    if [[ "$has_admin" != "yes" ]]; then
        if command -v capsh &>/dev/null; then
            capsh --print 2>/dev/null | grep -q cap_net_admin && has_admin=yes
            capsh --print 2>/dev/null | grep -q cap_net_raw && has_raw=yes
        elif [[ "$(id -u)" -eq 0 ]]; then
            has_admin=yes; has_raw=yes
        fi
    fi

    if [[ "$has_admin" != "yes" || "$has_raw" != "yes" ]]; then
        echo -e "  ${RD}This section needs cap_net_admin + cap_net_raw${R}"
        echo ""
        echo -e "  ${B}Option 1:${R} Run with sudo"
        echo -e "    ${DIM}sudo net-report --section wifi-scan${R}"
        echo ""
        echo -e "  ${B}Option 2:${R} Rebuild with security.wrappers (already in network.nix)"
        echo -e "    ${DIM}sudo nixos-rebuild switch --flake .#UwU${R}"
        echo -e "    ${DIM}Then the wrappers appear at /run/wrappers/bin/net-report-*${R}"
        echo ""
        echo -e "  ${B}Option 3:${R} Set capabilities on the tools directly"
        echo -e "    ${DIM}sudo setcap cap_net_admin,cap_net_raw+eip \$(which iw)${R}"
        echo -e "    ${DIM}sudo setcap cap_net_raw+eip \$(which tcpdump)${R}"
        echo -e "    ${DIM}sudo setcap cap_net_raw+eip \$(which aireplay-ng)${R}"
        return
    fi

    # Need tools
    if [[ -z "$IW_BIN" ]]; then
        echo -e "  ${RD}iw not found${R} — add pkgs.iw to environment.systemPackages"
        return
    fi
    if [[ -z "$AIREPLAY_BIN" ]]; then
        echo -e "  ${RD}aireplay-ng not found${R} — install aircrack-ng"
        echo -e "  ${DIM}Add pkgs.aircrack-ng to environment.systemPackages${R}"
        return
    fi
    if [[ -z "$TCPDUMP_BIN" ]]; then
        echo -e "  ${RD}tcpdump not found${R} — add to environment.systemPackages"
        return
    fi

    # Find the WiFi interface and its phy
    local wifi_iface wifi_phy ap_bssid ap_essid ap_channel
    wifi_iface=$( (nmcli -t -f DEVICE,TYPE,STATE device status 2>/dev/null || true) | grep -i wifi | grep connected | head -1 | cut -d: -f1 || true)

    if [[ -z "$wifi_iface" ]]; then
        echo -e "  ${RD}No connected WiFi interface found${R}"
        return
    fi

    wifi_phy=$(cat "/sys/class/net/${wifi_iface}/phy80211/name" 2>/dev/null || true)
    if [[ -z "$wifi_phy" ]]; then
        echo -e "  ${RD}Cannot find phy for ${wifi_iface}${R}"
        return
    fi

    # Get current AP info (BSSID, ESSID, channel)
    local ap_info
    ap_info=$( ("$IW_BIN" dev "$wifi_iface" link 2>/dev/null || true) )
    ap_bssid=$(echo "$ap_info" | grep -oP 'Connected to \K\S+' || true)
    ap_essid=$(echo "$ap_info" | grep -oP 'SSID: \K.*' || true)
    ap_channel=$(echo "$ap_info" | grep -oP 'freq: \K\d+' | awk '{printf "%d", ($1-2412)/5+1}' 2>/dev/null || true)
    # Better channel parsing from iw
    ap_channel=$( ("$IW_BIN" dev "$wifi_iface" info 2>/dev/null || true) | grep -oP 'channel \K\d+' || true)

    if [[ -z "$ap_bssid" || "$ap_bssid" == "Not connected." ]]; then
        echo -e "  ${RD}Not connected to a WiFi AP — cannot deauth${R}"
        echo -e "  ${DIM}Connect to WiFi first, then run this section${R}"
        return
    fi

    echo -e "  ${B}WiFi Interface:${R} ${wifi_iface} (${wifi_phy})"
    echo -e "  ${B}Connected AP:${R} ${ap_essid:-?} (${ap_bssid})"
    echo -e "  ${B}Channel:${R} ${ap_channel:-?}"
    echo ""

    # Create monitor mode interface
    local mon_iface="mon0"
    echo -e "  ${DIM}Setting up monitor mode on ${mon_iface}...${R}"

    # Clean up any existing monitor interface
    "$IW_BIN" dev "$mon_iface" del 2>/dev/null || true

    # Create monitor interface
    if ! "$IW_BIN" dev "$wifi_iface" interface add "$mon_iface" type monitor 2>/dev/null; then
        echo -e "  ${RD}Failed to create monitor interface${R}"
        # Show just "iw" instead of the full Nix store path
        local iw_short="iw"
        [[ "$IW_BIN" == /run/wrappers/bin/net-report-iw ]] && iw_short="net-report-iw"
        echo -e "  ${DIM}Try: ${iw_short} phy ${wifi_phy} interface add ${mon_iface} type monitor${R}"
        return
    fi

    # Set channel and bring up
    if [[ -n "$ap_channel" ]]; then
        "$IW_BIN" dev "$mon_iface" set channel "$ap_channel" 2>/dev/null || true
    fi
    ip link set "$mon_iface" up 2>/dev/null || true

    # Verify monitor mode is active
    local mon_type
    mon_type=$( ("$IW_BIN" dev "$mon_iface" info 2>/dev/null || true) | grep -oP 'type \K\S+' || true)
    if [[ "$mon_type" != "monitor" ]]; then
        echo -e "  ${RD}Monitor mode not active (type=${mon_type:-?})${R}"
        "$IW_BIN" dev "$mon_iface" del 2>/dev/null || true
        return
    fi

    echo -e "  ${GR}Monitor mode active on ${mon_iface} (channel ${ap_channel:-?})${R}"
    echo ""

    # Capture probe requests in background while sending deauth
    local tmpdir
    tmpdir=$(mktemp -d)
    local capture_file="${tmpdir}/probes.pcap"

    echo -e "  ${DIM}Capturing probe requests (10 second window)...${R}"

    # Start tcpdump in background — capture probe requests (type subtype 4 = probe req)
    # Probe request = subtype 0x04 in management frame (type 0x00)
    # Filter: wlan type m subtype probe-req
    ("$TCPDUMP_BIN" -i "$mon_iface" -e -nn -l 'type m subtype probe-req' -w "$capture_file" 2>/dev/null) &
    local tcpdump_pid=$!

    # Give tcpdump a moment to start
    sleep 1

    # Send deauth frames (5 deauth bursts, 0.5s apart)
    echo -e "  ${DIM}Sending deauth frames to ${ap_bssid}...${R}"
    "$AIREPLAY_BIN" --deauth 5 -a "$ap_bssid" "$mon_iface" >/dev/null 2>&1 || true

    # Wait for probes to come in (devices re-probe within 1-3 seconds of deauth)
    sleep 8

    # Stop tcpdump
    kill "$tcpdump_pid" 2>/dev/null || true
    wait "$tcpdump_pid" 2>/dev/null || true

    # Parse captured probe requests
    echo ""
    echo -e "  ${B}Discovered WiFi devices:${R}"
    echo ""
    printf "  %-20s %-25s %-10s %-12s %s\n" "MAC ADDRESS" "PROBED SSID" "SIGNAL" "VENDOR" "CHANNEL"
    printf "  %-20s %-25s %-10s %-12s %s\n" "-----------" "-----------" "------" "------" "-------"

    local device_count=0
    # Parse the pcap with tcpdump -r and extract: src MAC, SSID from probe req, signal
    # tcpdump -e shows: src MAC in "SA:" field, signal in antenna/radiotap headers
    ("$TCPDUMP_BIN" -r "$capture_file" -e -nn 2>/dev/null || true) | \
    awk '{
        mac="-"; ssid="-"; sig="-"; chan="-"
        # Extract source MAC (SA: field)
        for(i=1;i<=NF;i++) {
            if($i == "SA:") { mac=$(i+1); }
        }
        # Extract signal (radiotap header, look for dBm)
        for(i=1;i<=NF;i++) {
            if($i ~ /-[0-9]+dBm/) { sig=$i; }
        }
        # SSID is typically after "Probe Request" in the frame
        # tcpdump shows it as the SSID in quotes or as hex
        for(i=1;i<=NF;i++) {
            if($i == "Probe" && $(i+1) == "Request") {
                # SSID is usually further on the line, may be in quotes
                j=i+2
                while(j<=NF && $j !~ /SA:/) {
                    if($j ~ /^".*"$/) { ssid=$j; gsub(/"/,"",ssid); break }
                    j++
                }
            }
        }
        if(mac != "-") {
            printf "%s\t%s\t%s\t%s\t%s\n", mac, ssid, sig, "-", chan
        }
    }' | sort -u | while IFS=$'\t' read -r mac ssid sig vendor chan; do
        # Try to get vendor from first 3 octets of MAC (OUI lookup)
        local oui
        oui=$(echo "$mac" | cut -d: -f1-3 | tr 'a-f' 'A-F' 2>/dev/null || true)
        # Basic OUI lookup — we can't ship a full OUI database, but we can
        # check /etc/ethers or just show the OUI prefix
        vendor="${oui:-?}"

        printf "  %-20s %-25s %-10s %-12s %s\n" "$mac" "$(truncate_str "$ssid" 25)" "$sig" "$vendor" "$chan"
        device_count=$((device_count + 1))
    done

    echo ""
    if [[ $device_count -gt 0 ]]; then
        echo -e "  ${B}Discovered ${device_count} WiFi devices via probe requests${R}"
    else
        echo -e "  ${DIM}No probe requests captured${R}"
        echo -e "  ${DIM}(devices may have reconnected too fast, or pcap parsing issue)${R}"
        # Show raw pcap stats as fallback
        local pcap_lines
        pcap_lines=$( ("$TCPDUMP_BIN" -r "$capture_file" -nn 2>/dev/null || true) | wc -l)
        if [[ $pcap_lines -gt 0 ]]; then
            echo -e "  ${DIM}Raw pcap: ${pcap_lines} frames captured${R}"
            echo -e "  ${DIM}Run: tcpdump -r ${capture_file} -e -nn${R}"
        fi
    fi

    # Cleanup
    echo ""
    echo -e "  ${DIM}Cleaning up monitor interface...${R}"
    "$IW_BIN" dev "$mon_iface" del 2>/dev/null || true
    rm -rf "$tmpdir"

    # Also parse with tshark if available (better SSID extraction)
    if command -v tshark &>/dev/null && [[ -f "$capture_file" ]]; then
        echo ""
        echo -e "  ${B}Detailed probe request analysis (tshark):${R}"
        echo -e "  ${DIM}(re-reading pcap — this is from the in-memory copy, already cleaned up)${R}"
    fi
}

# --- Routing table (parsed) ------------------------------------------------
section_routes() {
    header "ROUTING TABLE"
    if [[ "$VERBOSE" == "yes" ]]; then
        run "IPv4 routes" ip route show
        run "IPv4 routes (local)" ip route show table local 2>/dev/null || true
        run "IPv6 routes" ip -6 route show
        run "IPv6 routes (local)" ip -6 route show table local 2>/dev/null || true
        run "Rule policies (IPv4)" ip rule show
        run "Rule policies (IPv6)" ip -6 rule show
        return
    fi

    # IPv4 routes table
    echo -e "  ${B}IPv4 Routes (main):${R}"
    printf "  %-20s %-15s %-12s %-8s %-8s %s\n" "DESTINATION" "GATEWAY" "INTERFACE" "METRIC" "SOURCE" "PROTO"
    printf "  %-20s %-15s %-12s %-8s %-8s %s\n" "----------" "-------" "---------" "------" "------" "-----"
    ip route show 2>/dev/null | while read -r dest via gw dev iface metric src source proto rest; do
        # This is a simplification — ip route output is complex
        # Use awk for more robust parsing
        :
    done
    # Actually just use awk to parse ip route output into a table
    ip route show 2>/dev/null | awk '{
        dest=$1; gw="-"; iface="-"; metric="-"; src="-"; proto="-"
        for(i=2;i<=NF;i++) {
            if($i=="via") {gw=$(i+1); i++}
            else if($i=="dev") {iface=$(i+1); i++}
            else if($i=="metric") {metric=$(i+1); i++}
            else if($i=="src") {src=$(i+1); i++}
            else if($i=="proto") {proto=$(i+1); i++}
        }
        printf "  %-20s %-15s %-12s %-8s %-15s %s\n", dest, gw, iface, metric, src, proto
    }'

    echo ""
    echo -e "  ${B}IPv6 Routes (main):${R}"
    ip -6 route show 2>/dev/null | awk '{
        dest=$1; gw="-"; iface="-"; metric="-"; proto="-"
        for(i=2;i<=NF;i++) {
            if($i=="via") {gw=$(i+1); i++}
            else if($i=="dev") {iface=$(i+1); i++}
            else if($i=="metric") {metric=$(i+1); i++}
            else if($i=="proto") {proto=$(i+1); i++}
        }
        printf "  %-30s %-15s %-12s %-8s %s\n", dest, gw, iface, metric, proto
    }'

    echo ""
    run_silent "Policy rules (IPv4)" ip rule show
    run_silent "Policy rules (IPv6)" ip -6 rule show
}

# --- DNS / name resolution -------------------------------------------------
section_dns() {
    header "DNS / NAME RESOLUTION"

    # resolvectl (systemd-resolved)
    if command -v resolvectl &>/dev/null && systemctl is-active systemd-resolved &>/dev/null 2>&1; then
        echo -e "  ${B}resolvectl status:${R}"
        (resolvectl status 2>/dev/null || true) | sed 's/^/    /'
        echo ""
        echo -e "  ${B}resolvectl statistics:${R}"
        (resolvectl statistics 2>/dev/null || true) | sed 's/^/    /'
        echo ""
        echo -e "  ${B}resolvectl domain:${R}"
        (resolvectl domain 2>/dev/null || true) | sed 's/^/    /'
        echo ""
        echo -e "  ${B}resolvectl dns:${R}"
        (resolvectl dns 2>/dev/null || true) | sed 's/^/    /'
    else
        echo -e "  ${DIM}systemd-resolved not active${R}"
    fi
    echo ""

    # /etc/resolv.conf
    echo -e "  ${B}resolv.conf:${R}"
    if [[ -f /etc/resolv.conf ]]; then
        (cat /etc/resolv.conf 2>/dev/null || true) | sed 's/^/    /'
    else
        echo -e "    ${DIM}(not found)${R}"
    fi
    echo ""

    # /etc/hosts
    echo -e "  ${B}hosts:${R}"
    if [[ -f /etc/hosts ]]; then
        (cat /etc/hosts 2>/dev/null || true) | sed 's/^/    /'
    else
        echo -e "    ${DIM}(not found)${R}"
    fi
    echo ""

    # DNS resolution timing test
    echo -e "  ${B}DNS lookup timing:${R}"
    local dns_time dns_ip
    dns_time=$(dig +short +time=3 +tries=1 +stats A example.com 2>/dev/null | grep -oP 'Query time: \K\d+' || echo "?")
    dns_ip=$(dig +short +time=3 +tries=1 A example.com 2>/dev/null | head -1 || echo "?")
    if [[ "$dns_time" != "?" ]]; then
        local speed_color="$GR"
        [[ $dns_time -gt 50 ]] && speed_color="$YE"
        [[ $dns_time -gt 200 ]] && speed_color="$RD"
        echo -e "  example.com → ${dns_ip} (${speed_color}${dns_time}ms${R})"
    else
        echo -e "  ${RD}DNS resolution failed${R}"
    fi

    # Reverse DNS for gateway
    local default_gw
    default_gw=$(ip route show default 2>/dev/null | awk '{print $3; exit}' || echo "")
    if [[ -n "$default_gw" ]]; then
        local rdns
        rdns=$(dig +short +time=3 +tries=1 -x "$default_gw" 2>/dev/null | head -1 || echo "")
        if [[ -n "$rdns" ]]; then
            echo -e "  ${default_gw} → ${rdns}"
        else
            echo -e "  ${default_gw} → ${DIM}(no PTR record)${R}"
        fi
    fi
    echo ""
}

# --- ARP / neighbor table (parsed) -----------------------------------------
section_neighbors() {
    header "ARP / NEIGHBOR TABLE"

    if [[ "$VERBOSE" == "yes" ]]; then
        run "IPv4 neighbors (ARP)" ip neigh show
        run "IPv6 neighbors" ip -6 neigh show
        return
    fi

    echo -e "  ${B}IPv4 Neighbors (ARP):${R}"
    printf "  %-18s %-14s %-12s %-10s %s\n" "IP ADDRESS" "MAC ADDRESS" "INTERFACE" "STATE" " "
    printf "  %-18s %-14s %-12s %-10s %s\n" "----------" "------------" "---------" "-----" " "
    ip neigh show 2>/dev/null | awk '{
        ip=$1; mac="-"; iface="-"; state="-"
        for(i=2;i<=NF;i++) {
            if($i=="lladdr") {mac=$(i+1); i++}
            else if($i=="dev") {iface=$(i+1); i++}
        }
        state=$NF
        printf "  %-18s %-14s %-12s %-10s\n", ip, mac, iface, state
    }' || echo -e "  ${DIM}(none)${R}"

    echo ""
    echo -e "  ${B}IPv6 Neighbors:${R}"
    ip -6 neigh show 2>/dev/null | awk '{
        ip=$1; mac="-"; iface="-"; state="-"
        for(i=2;i<=NF;i++) {
            if($i=="lladdr") {mac=$(i+1); i++}
            else if($i=="dev") {iface=$(i+1); i++}
        }
        state=$NF
        printf "  %-40s %-14s %-12s %-10s\n", ip, mac, iface, state
    }' || echo -e "  ${DIM}(none)${R}"
}

# --- Sockets / connections (with state summary) ----------------------------
section_sockets() {
    header "SOCKETS / CONNECTIONS"

    if [[ "$VERBOSE" == "yes" ]]; then
        run "Listening TCP" ss -tlnp
        run "Listening UDP" ss -ulnp
        run "Established TCP" ss -tnp state established
        run "Established UDP" ss -unp
        run "All sockets summary" ss -s
        run "Raw sockets" ss -wlp 2>/dev/null || true
        return
    fi

    # TCP connection state summary
    echo -e "  ${B}TCP Connection State Summary:${R}"
    local total_tcp=0
    while read -r count state; do
        local state_color="$BR"
        case "$state" in
            ESTAB) state_color="$GR" ;;
            LISTEN) state_color="$BL" ;;
            TIME-WAIT|CLOSE-WAIT) state_color="$YE" ;;
            SYN-SENT|SYN-RECV) state_color="$CY" ;;
        esac
        printf "  ${state_color}%-16s${R} %4d\n" "$state" "$count"
        total_tcp=$((total_tcp + count))
    done < <((ss -tanH 2>/dev/null || true) | awk '{print $1}' | sort | uniq -c | sort -rn | awk '{print $1, $2}')
    echo -e "  ${DIM}Total: ${total_tcp}${R}"
    echo ""

    # Listening ports table
    echo -e "  ${B}Listening Ports:${R}"
    printf "  %-6s %-22s %-22s %s\n" "PROTO" "LOCAL ADDRESS" "PROCESS" "SERVICE"
    printf "  %-6s %-22s %-22s %s\n" "-----" "-------------" "-------" "-------"

    # TCP
    (ss -tlnH 2>/dev/null || true) | awk '{
        split($4, a, ":"); port=a[length(a)]
        proc="-"; for(i=6;i<=NF;i++) if($i ~ /users/) {
            # Extract process name between first pair of quotes: users:(("name",pid=...))
            sub(/.*\(\("/, "", $i); sub(/".*/, "", $i); proc=$i
        }
        svc="-"
        cmd = "getent services " port " 2>/dev/null"
        cmd | getline svc; close(cmd)
        split(svc, s, " "); svc=s[1]
        if(svc=="") svc="-"
        printf "  %-6s %-22s %-22s %s\n", "TCP", $4, proc, svc
    }'

    # UDP
    (ss -ulnH 2>/dev/null || true) | awk '{
        split($4, a, ":"); port=a[length(a)]
        proc="-"; for(i=6;i<=NF;i++) if($i ~ /users/) {
            sub(/.*\(\("/, "", $i); sub(/".*/, "", $i); proc=$i
        }
        svc="-"
        cmd = "getent services " port " 2>/dev/null"
        cmd | getline svc; close(cmd)
        split(svc, s, " "); svc=s[1]
        if(svc=="") svc="-"
        printf "  %-6s %-22s %-22s %s\n", "UDP", $4, proc, svc
    }'

    echo ""
    echo -e "  ${B}Established Connections (top 20):${R}"
    printf "  %-22s %-22s %s\n" "LOCAL" "REMOTE" "PROCESS"
    printf "  %-22s %-22s %s\n" "-----" "------" "-------"
    (ss -tnpH state established 2>/dev/null || true) | head -20 | awk '{
        proc="-"; for(i=5;i<=NF;i++) if($i ~ /users/) {
            sub(/.*\(\("/, "", $i); sub(/".*/, "", $i); proc=$i
        }
        printf "  %-22s %-22s %s\n", $3, $4, proc
    }'

    echo ""
    run_silent "Socket summary" ss -s
}

# --- Conntrack (connection tracking) --------------------------------------
section_conntrack() {
    header "CONNTRACK (connection tracking)"
    if ! command -v conntrack &>/dev/null; then
        echo -e "  ${DIM}conntrack not found${R}"
        return
    fi

    # Summary counts
    local ct_total ct_max ct_tcp ct_udp ct_icmp
    ct_total=$( (conntrack -L 2>/dev/null || true) | grep -c . || true)
    [[ -z "$ct_total" ]] && ct_total=0
    ct_max=$(cat /proc/sys/net/nf_conntrack_max 2>/dev/null || echo "?")
    ct_tcp=$( (conntrack -L -p tcp 2>/dev/null || true) | grep -c . || true)
    [[ -z "$ct_tcp" ]] && ct_tcp=0
    ct_udp=$( (conntrack -L -p udp 2>/dev/null || true) | grep -c . || true)
    [[ -z "$ct_udp" ]] && ct_udp=0
    ct_icmp=$( (conntrack -L -p icmp 2>/dev/null || true) | grep -c . || true)
    [[ -z "$ct_icmp" ]] && ct_icmp=0

    if [[ "$ct_total" == "0" ]]; then
        echo -e "  ${RD}Cannot read conntrack table (need root)${R}"
        echo -e "  ${DIM}Run: sudo net-report --section conntrack${R}"
        echo ""
        echo -e "  ${DIM}Conntrack max entries: ${ct_max}${R}"
        # Still show sysctl settings
        echo ""
        echo -e "  ${B}Sysctl settings:${R}"
        for key in /proc/sys/net/nf_conntrack_max \
                   /proc/sys/net/netfilter/nf_conntrack_tcp_timeout_established \
                   /proc/sys/net/netfilter/nf_conntrack_tcp_timeout_time_wait \
                   /proc/sys/net/netfilter/nf_conntrack_udp_timeout; do
            if [[ -f "$key" ]]; then
                printf "  %-60s %s\n" "$(basename "$key")" "$(cat "$key" 2>/dev/null)"
            fi
        done
        return
    fi

    # Percentage
    local pct="-"
    if [[ "$ct_max" != "?" && "$ct_max" -gt 0 ]]; then
        pct=$(awk "BEGIN{printf \"%.1f%%\", ($ct_total/$ct_max)*100}")
    fi

    printf "  %-20s %s\n" "Total entries:" "$ct_total"
    printf "  %-20s %s\n" "Max entries:" "$ct_max"
    printf "  %-20s %s\n" "Table usage:" "$pct"
    printf "  %-20s %s\n" "TCP flows:" "$ct_tcp"
    printf "  %-20s %s\n" "UDP flows:" "$ct_udp"
    printf "  %-20s %s\n\n" "ICMP flows:" "$ct_icmp"

    # State breakdown
    echo -e "  ${B}State Breakdown:${R}"
    conntrack -L 2>/dev/null | awk '{
        for(i=1;i<=NF;i++) {
            if($i ~ /state=/) {gsub(/.*=/,"",$i); print $i}
        }
    }' | sort | uniq -c | sort -rn | while read -r count state; do
        local state_color="$BR"
        case "$state" in
            ESTABLISHED|ASSURED) state_color="$GR" ;;
            TIME_WAIT|CLOSE) state_color="$YE" ;;
            NEW|SYN_SENT) state_color="$CY" ;;
        esac
        printf "  ${state_color}%-16s${R} %4d\n" "$state" "$count"
    done

    # Conntrack sysctl settings
    echo ""
    echo -e "  ${B}Sysctl settings:${R}"
    for key in \
        /proc/sys/net/nf_conntrack_max \
        /proc/sys/net/netfilter/nf_conntrack_tcp_timeout_established \
        /proc/sys/net/netfilter/nf_conntrack_tcp_timeout_time_wait \
        /proc/sys/net/netfilter/nf_conntrack_udp_timeout \
        /proc/sys/net/netfilter/nf_conntrack_checksum; do
        if [[ -f "$key" ]]; then
            printf "  %-60s %s\n" "$(basename "$key")" "$(cat "$key" 2>/dev/null)"
        fi
    done

    if [[ "$VERBOSE" == "yes" ]]; then
        echo ""
        run "Full conntrack table" conntrack -L
        run "Conntrack statistics" conntrack -S
        run "Conntrack expect" conntrack -L -f expect 2>/dev/null || true
    fi
}

# --- Firewall (nftables) ---------------------------------------------------
section_firewall() {
    header "FIREWALL (nftables)"

    if [[ "$VERBOSE" == "yes" ]]; then
        run "nftables ruleset" nft list ruleset
        run "nftables tables" nft list tables 2>/dev/null || true
        if command -v iptables &>/dev/null; then
            run "iptables filter (fallback)" iptables -L -n -v 2>/dev/null || true
            run "iptables nat (fallback)" iptables -t nat -L -n -v 2>/dev/null || true
        fi
        return
    fi

    # Table list with rule counts
    echo -e "  ${B}nftables Tables:${R}"
    local nft_ok=no
    if nft list tables 2>/dev/null | head -1 &>/dev/null; then
        nft_ok=yes
    fi

    if [[ "$nft_ok" == "no" ]]; then
        echo -e "  ${RD}Cannot read nftables (need root)${R}"
        echo -e "  ${DIM}Run with sudo for full firewall info${R}"
        return
    fi

    nft list tables 2>/dev/null | awk '{
        gsub(/table /,""); gsub(/ \{/,""); print "  " $0
    }'

    echo ""
    echo -e "  ${B}Ruleset (full):${R}"
    nft list ruleset 2>&1 || echo -e "  ${RD}(failed — need root)${R}"
}

# --- NetworkManager --------------------------------------------------------
section_nm() {
    header "NETWORKMANAGER"
    if [[ "$VERBOSE" == "yes" ]]; then
        run "NM general status" nmcli general status
        run "NM device status (all fields)" nmcli -f all device status
        run "NM connections (active)" nmcli connection show --active
        run "NM connections (all)" nmcli connection show
        return
    fi

    # General
    local nm_state nm_conn
    nm_state=$(nmcli -t -f STATE general status 2>/dev/null || echo "?")
    nm_conn=$(nmcli -t -f CONNECTIVITY general status 2>/dev/null || echo "?")
    echo -e "  State:         $(color_status "$nm_state")"
    echo -e "  Connectivity:  $(color_status "$nm_conn")"
    echo ""

    # Device table
    echo -e "  ${B}Devices:${R}"
    printf "  %-14s %-14s %-12s %-20s %s\n" "DEVICE" "TYPE" "STATE" "CONNECTION" "IP"
    printf "  %-14s %-14s %-12s %-20s %s\n" "------" "----" "-----" "----------" "--"
    nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device status 2>/dev/null | while IFS=: read -r dev type state conn; do
        local ip4
        ip4=$(ip -4 -br addr show "$dev" 2>/dev/null | awk '{print $3}' || echo "-")
        [[ -z "$ip4" ]] && ip4="-"
        printf "  %-14s %-14s %-12s %-20s %s\n" "$dev" "$type" "$(color_status "$state")" "$conn" "$ip4"
    done

    echo ""
    echo -e "  ${B}Active Connections:${R}"
    printf "  %-25s %-14s %-14s %-14s %s\n" "NAME" "TYPE" "DEVICE" "UUID" "STATE"
    printf "  %-25s %-14s %-14s %-14s %s\n" "----" "----" "------" "----" "-----"
    nmcli -t -f NAME,TYPE,DEVICE,UUID,STATE connection show --active 2>/dev/null | while IFS=: read -r name type dev uuid state; do
        printf "  %-25s %-14s %-14s %-14s %s\n" \
            "$(truncate_str "$name" 25)" "$type" "$dev" "$(truncate_str "$uuid" 14)" "$(color_status "$state")"
    done
}

# --- VPN / tunnels --------------------------------------------------------
section_vpn() {
    header "VPN / TUNNELS"

    # IVPN
    if command -v ivpn &>/dev/null; then
        echo -e "  ${B}IVPN:${R}"
        local ivpn_state ivpn_firewall
        ivpn_state=$(ivpn status 2>/dev/null | head -1 | awk -F: '{gsub(/^ +| +$/,"",$2); print $2}' || echo "Unknown")
        echo -e "    State:     $(color_status "$ivpn_state")"
        ivpn status 2>/dev/null | tail -n +2 | while read -r line; do
            local key val
            key=$(echo "$line" | awk -F: '{print $1}' | xargs)
            val=$(echo "$line" | awk -F: '{print $2}' | xargs)
            [[ -n "$val" ]] && printf "    %-12s %s\n" "$key" "$val"
        done
        echo ""
    fi

    # WireGuard
    if command -v wg &>/dev/null; then
        echo -e "  ${B}WireGuard:${R}"
        local wg_out
        wg_out=$(wg show all 2>/dev/null || true)
        if [[ -n "$wg_out" ]]; then
            echo "$wg_out" | sed 's/^/    /'
        else
            echo -e "    ${DIM}No WireGuard interfaces${R}"
        fi
        echo ""
    fi

    # OpenVPN
    if pgrep -x openvpn &>/dev/null; then
        echo -e "  ${B}OpenVPN:${R}"
        ps aux | grep -i '[o]penvpn' | awk '{printf "    PID: %-8s %s\n", $2, $11" "$12" "$13}'
        echo ""
    fi

    # TUN/TAP interfaces
    local tun_ifaces tap_ifaces
    tun_ifaces=$(ip -o link show type tun 2>/dev/null | awk -F': ' '{print $2}' || true)
    tap_ifaces=$(ip -o link show type tap 2>/dev/null | awk -F': ' '{print $2}' || true)
    echo -e "  ${B}TUN/TAP interfaces:${R}"
    if [[ -n "$tun_ifaces" ]]; then
        echo "    TUN: $tun_ifaces"
    fi
    if [[ -n "$tap_ifaces" ]]; then
        echo "    TAP: $tap_ifaces"
    fi
    if [[ -z "$tun_ifaces" && -z "$tap_ifaces" ]]; then
        echo -e "    ${DIM}None${R}"
    fi

    # Any VPN-like interfaces
    echo ""
    echo -e "  ${B}All VPN-like interfaces:${R}"
    local vpn_ifaces
    vpn_ifaces=$(ip -o link show 2>/dev/null | grep -iE 'tun|tap|wg|ppp|ipsec|ivpn' | awk -F': ' '{print $2}' || true)
    if [[ -n "$vpn_ifaces" ]]; then
        echo "    $vpn_ifaces"
    else
        echo -e "    ${DIM}None found${R}"
    fi
}

# --- RFKill ----------------------------------------------------------------
section_rfkill() {
    header "RFKILL (radio switches)"
    if ! command -v rfkill &>/dev/null; then
        echo -e "  ${DIM}rfkill not found${R}"
        return
    fi

    printf "  %-6s %-20s %-14s %-14s %s\n" "IDX" "DEVICE" "SOFT BLOCK" "HARD BLOCK" "TYPE"
    printf "  %-6s %-20s %-14s %-14s %s\n" "---" "------" "---------" "---------" "----"
    rfkill list 2>/dev/null | awk '
    BEGIN { idx=""; dev=""; type="" }
    /^[0-9]+:/ {
        if (idx != "") { printf "  %-6s %-20s %-14s %-14s %s\n", idx, dev, soft, hard, type }
        split($0, a, ":")
        idx=a[1]
        dev=$0; sub(/^[0-9]+: /,"",dev); sub(/: .*$/,"",dev)
        type=$0; sub(/^.*: /,"",type)
        soft="-"; hard="-"
    }
    /Soft blocked/ { soft=($0 ~ /yes/) ? "yes" : "no" }
    /Hard blocked/ { hard=($0 ~ /yes/) ? "yes" : "no" }
    END { if (idx != "") { printf "  %-6s %-20s %-14s %-14s %s\n", idx, dev, soft, hard, type } }
    '
}

# --- Bridge / bonding ------------------------------------------------------
section_bridge() {
    header "BRIDGE / BONDING"

    if command -v bridge &>/dev/null; then
        local bridge_out
        bridge_out=$(bridge link show 2>/dev/null || true)
        if [[ -n "$bridge_out" ]]; then
            run "Bridge links" echo "$bridge_out"
        else
            echo -e "  ${DIM}No bridge interfaces${R}"
        fi

        run_silent "Bridge VLANs" bridge vlan show
        # FDB and MDB are very verbose — only show in --verbose mode
        if [[ "$VERBOSE" == "yes" ]]; then
            run_silent "Bridge FDB" bridge fdb show
            run_silent "Bridge MDB" bridge mdb show
        fi
    else
        echo -e "  ${DIM}bridge command not found${R}"
    fi

    # Bonding info
    local bond_found=no
    for f in /proc/net/bonding/*; do
        if [[ -f "$f" ]]; then
            bond_found=yes
            run "Bond: $(basename "$f")" cat "$f"
        fi
    done
    [[ "$bond_found" == "no" ]] && echo -e "  ${DIM}No bonding interfaces${R}"
}

# --- Multicast group memberships ------------------------------------------
section_multicast() {
    header "MULTICAST GROUPS"
    local mc_out
    mc_out=$(ip maddr show 2>/dev/null || true)
    if [[ -z "$mc_out" ]]; then
        echo -e "  ${DIM}No multicast groups${R}"
        return
    fi

    if [[ "$VERBOSE" == "yes" ]]; then
        # Full listing: every individual MAC address
        echo -e "  ${B}IPv4/IPv6 Multicast Memberships:${R}"
        echo ""
        ip maddr show 2>/dev/null | awk '
        /^[0-9]+:/ { iface=$2; gsub(/:/,"",iface); printf "\n  %s\n", iface }
        /inet[46]/ { printf "    %-8s %s\n", $1, $2 }
        /link/ { printf "    %-8s %s\n", "link", $2 }
        '
        echo ""
    else
        # Summary: count of multicast groups per interface
        echo -e "  ${B}Multicast group count per interface:${R}"
        echo ""
        printf "  %-20s %s\n" "INTERFACE" "GROUPS"
        printf "  %-20s %s\n" "---------" "------"
        ip maddr show 2>/dev/null | awk '
        /^[0-9]+:/ {
            if (iface != "" && count > 0) printf "  %-20s %d\n", iface, count
            iface=$2; gsub(/:/,"",iface); count=0
        }
        /inet[46]|link/ { count++ }
        END { if (iface != "" && count > 0) printf "  %-20s %d\n", iface, count }
        '
        echo ""
    fi
}

# --- Network sysctl summary ------------------------------------------------
section_sysctl() {
    header "NETWORK SYSCTL (kernel tunables)"

    echo -e "  ${B}IPv4:${R}"
    local sysctls_ipv4=(
        "net.ipv4.ip_forward"
        "net.ipv4.conf.all.forwarding"
        "net.ipv4.conf.default.rp_filter"
        "net.ipv4.conf.all.rp_filter"
        "net.ipv4.tcp_keepalive_time"
        "net.ipv4.tcp_keepalive_intvl"
        "net.ipv4.tcp_keepalive_probes"
        "net.ipv4.tcp_fin_timeout"
        "net.ipv4.tcp_tw_reuse"
        "net.ipv4.tcp_max_syn_backlog"
        "net.ipv4.tcp_syncookies"
        "net.ipv4.ip_local_port_range"
        "net.ipv4.tcp_fastopen"
    )
    for key in "${sysctls_ipv4[@]}"; do
        local val
        val=$(sysctl "$key" 2>/dev/null | awk -F'= ' '{print $2}' || echo "-")
        printf "  %-45s %s\n" "$key" "$val"
    done

    echo ""
    echo -e "  ${B}IPv6:${R}"
    local sysctls_ipv6=(
        "net.ipv6.conf.all.forwarding"
        "net.ipv6.conf.all.disable_ipv6"
        "net.ipv6.conf.all.use_tempaddr"
        "net.ipv6.conf.default.use_tempaddr"
        "net.ipv6.conf.all.accept_ra"
        "net.ipv6.conf.default.accept_ra"
    )
    for key in "${sysctls_ipv6[@]}"; do
        local val
        val=$(sysctl "$key" 2>/dev/null | awk -F'= ' '{print $2}' || echo "-")
        printf "  %-45s %s\n" "$key" "$val"
    done

    echo ""
    echo -e "  ${B}Conntrack:${R}"
    local ct_keys=(
        "/proc/sys/net/nf_conntrack_max"
        "/proc/sys/net/netfilter/nf_conntrack_checksum"
        "/proc/sys/net/netfilter/nf_conntrack_tcp_loose"
    )
    for key in "${ct_keys[@]}"; do
        if [[ -f "$key" ]]; then
            printf "  %-45s %s\n" "$(basename "$key")" "$(cat "$key" 2>/dev/null)"
        fi
    done
}

# --- Kernel network messages (dmesg) --------------------------------------
section_kernel() {
    header "KERNEL NETWORK MESSAGES"
    local dmesg_out
    dmesg_out=$(dmesg -T 2>/dev/null | grep -iE 'net|eth|wifi|wlan|dhcp|dns|link|vlan|bridge|bond|tun|firewall|nft|drop|nf_|conn' | tail -30 || true)
    if [[ -n "$dmesg_out" ]]; then
        echo "$dmesg_out" | while read -r line; do
            echo "  $line"
        done
    else
        echo -e "  ${DIM}No recent network-related kernel messages${R}"
    fi
}

# --- Public IP / internet egress ------------------------------------------
section_public() {
    header "PUBLIC IP / INTERNET EGRESS"
    if [[ "$PUBLIC" != "yes" ]]; then
        echo "  (skipped — --no-public)"
        return
    fi

    start_spinner "Fetching public IP"
    local pub4 pub6
    pub4=$( (curl -s4 --max-time 5 https://ifconfig.me 2>/dev/null || true) )
    [[ -z "$pub4" ]] && pub4="(failed)"
    pub6=$( (curl -s6 --max-time 5 https://ifconfig.me 2>/dev/null || true) )
    [[ -z "$pub6" ]] && pub6="(failed)"
    stop_spinner

    echo -e "  ${B}Public IPv4:${R}  $pub4"
    echo -e "  ${B}Public IPv6:${R}  $pub6"

    # Whois/ASN info (quick)
    if [[ "$pub4" != "(failed)" ]] && command -v dig &>/dev/null; then
        local rdns asn
        rdns=$(dig +short +time=3 +tries=1 -x "$pub4" 2>/dev/null | head -1 || echo "")
        if [[ -n "$rdns" ]]; then
            echo -e "  ${B}rDNS:${R}       $rdns"
        else
            echo -e "  ${B}rDNS:${R}       ${DIM}(no PTR)${R}"
        fi
    fi

    echo ""
    local http_code
    http_code=$( (curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://connectivity-check.ubuntu.com 2>/dev/null || true) )
    [[ -z "$http_code" ]] && http_code="000"
    if [[ "$http_code" == "204" ]]; then
        color_check yes "HTTP connectivity check passed (204)"
    else
        color_check no "HTTP connectivity check failed (HTTP $http_code)"
    fi
}

# --- Host identity (all hostnames this device is known by) ----------------
section_host-identity() {
    header "HOST IDENTITY"

    local static_host transient_host pretty_host fqdn hostnamectl_out
    static_host=$(hostnamectl 2>/dev/null | grep -oP 'Static hostname: \K.*' || echo "?")
    transient_host=$(hostnamectl 2>/dev/null | grep -oP 'Transient hostname: \K.*' || echo "(none)")
    pretty_host=$(hostnamectl 2>/dev/null | grep -oP 'Pretty hostname: \K.*' || echo "(none)")
    fqdn=$(hostname -f 2>/dev/null || hostname 2>/dev/null || echo "?")

    # DHCP hostname broadcast (from NM connection profiles)
    # Only show ethernet and wifi connections — lo, wgivpn, etc. don't use DHCP
    local dhcp_host dhcp_hosts=""
    # nmcli -g UUID,NAME,TYPE returns "UUID:NAME:TYPE" (colon-separated)
    while IFS=: read -r uuid name conn_type; do
        [[ -z "$uuid" ]] && continue
        # Only show 802-3-ethernet and 802-11-wireless connections
        [[ "$conn_type" != "802-3-ethernet" && "$conn_type" != "802-11-wireless" ]] && continue
        local dh
        dh=$( (nmcli -g ipv4.dhcp-hostname connection show "$uuid" 2>/dev/null || true) )
        # nmcli -g returns just the value, or empty if not set
        if [[ -n "$dh" && "$dh" != "--" ]]; then
            dhcp_hosts="${dhcp_hosts}${name}:${dh}\n"
        fi
    done < <( (nmcli -g UUID,NAME,TYPE connection show 2>/dev/null || true) )

    # mDNS/Avahi hostname (if avahi-daemon is running)
    local mdns_host
    if command -v avahi-resolve &>/dev/null; then
        mdns_host=$(avahi-resolve -n "$(hostname).local" 2>/dev/null | awk '{print $2}' || echo "(not resolvable)")
    else
        mdns_host="(avahi not available)"
    fi

    # Hardware info
    local hw_vendor hw_product
    hw_vendor=$(hostnamectl 2>/dev/null | grep -oP 'Hardware Vendor: \K.*' || echo "-")
    hw_product=$(hostnamectl 2>/dev/null | grep -oP 'Hardware Model: \K.*' || echo "-")

    printf "  %-22s %s\n" "Static hostname:" "$static_host"
    printf "  %-22s %s\n" "Transient hostname:" "$transient_host"
    printf "  %-22s %s\n" "Pretty hostname:" "$pretty_host"
    printf "  %-22s %s\n" "FQDN:" "$fqdn"
    printf "  %-22s %s\n" "mDNS hostname:" "$mdns_host"
    printf "  %-22s %s\n" "Hardware vendor:" "$hw_vendor"
    printf "  %-22s %s\n" "Hardware model:" "$hw_product"

    # DHCP hostnames (what other devices see you as)
    echo ""
    echo -e "  ${B}DHCP hostnames (broadcast to each network):${R}"
    if [[ -n "$dhcp_hosts" ]]; then
        # Parse "name:hostname" pairs and format with column alignment
        echo -e "$dhcp_hosts" | while IFS=: read -r name dh; do
            [[ -z "$name" ]] && continue
            printf "    %-34s %s\n" "$name:" "$dh"
        done
    else
        echo -e "    ${DIM}(no custom DHCP hostname set)${R}"
    fi

    # Chassis type (laptop/desktop/server)
    echo ""
    local chassis
    chassis=$(hostnamectl 2>/dev/null | grep -oP 'Chassis: \K.*' || echo "-")
    printf "  %-22s %s\n" "Chassis:" "$chassis"

    # Operating system
    local os_info
    os_info=$(hostnamectl 2>/dev/null | grep -oP 'Operating System: \K.*' || echo "-")
    printf "  %-22s %s\n" "OS:" "$os_info"
    local kernel_ver
    kernel_ver=$(hostnamectl 2>/dev/null | grep -oP 'Kernel: \K.*' || echo "-")
    printf "  %-22s %s\n" "Kernel:" "$kernel_ver"
}

# --- Switch info (from LLDP — firmware, capabilities, port details) -------
section_switch-info() {
    header "SWITCH / UPSTREAM DEVICE INFO"
    if ! command -v lldpctl &>/dev/null; then
        echo -e "  ${RD}lldpctl not found${R} — install lldpd"
        return
    fi

    local lldp_out
    lldp_out=$( (lldpctl 2>/dev/null || true) )
    if [[ -z "$lldp_out" ]] || [[ "$lldp_out" == *"No LLDP neighbors"* ]]; then
        echo -e "  ${DIM}No LLDP neighbors discovered — switch may not broadcast LLDP${R}"
        echo -e "  ${DIM}Try: sudo lldpd -c  (enable CDP for Cisco switches)${R}"
        return
    fi

    # Parse each neighbor block
    local cur_iface=""
    while IFS= read -r line; do
        if [[ "$line" =~ ^Interface: ]]; then
            cur_iface=$(echo "$line" | awk -F',' '{print $1}' | awk '{print $2}')
            echo ""
            echo -e "  ${B}═══ ${cur_iface} ═══${R}"
        elif [[ "$line" =~ ^[[:space:]]+ChassisID: ]]; then
            local chassis_id
            chassis_id=$(echo "$line" | awk '{print $2, $3}' | sed 's/mac //')
            printf "  %-20s %s\n" "Chassis ID:" "$chassis_id"
        elif [[ "$line" =~ ^[[:space:]]+SysName: ]]; then
            local sysname
            sysname=$(echo "$line" | sed 's/^[[:space:]]*SysName:[[:space:]]*//')
            printf "  %-20s ${GR}%s${R}\n" "System name:" "$sysname"
        elif [[ "$line" =~ ^[[:space:]]+SysDescr: ]]; then
            local sysdescr
            sysdescr=$(echo "$line" | sed 's/^[[:space:]]*SysDescr:[[:space:]]*//')
            printf "  %-20s %s\n" "System description:" "$sysdescr"
            # Try to extract firmware/version from common patterns
            local fw_ver=""
            fw_ver=$(echo "$sysdescr" | grep -oiE '([0-9]+\.[0-9]+(\.[0-9]+)?(\.[0-9]+)?|v[0-9]+(\.[0-9]+)*|version [0-9.]+)' | head -1 || true)
            if [[ -n "$fw_ver" ]]; then
                printf "  %-20s ${YE}%s${R}\n" "Firmware version:" "$fw_ver"
            fi
        elif [[ "$line" =~ ^[[:space:]]+MgmtIP: ]]; then
            local mgmt_ip
            mgmt_ip=$(echo "$line" | awk '{print $2}')
            printf "  %-20s ${BL}%s${R}\n" "Management IP:" "$mgmt_ip"
        elif [[ "$line" =~ ^[[:space:]]+MgmtIface: ]]; then
            local mgmt_iface
            mgmt_iface=$(echo "$line" | awk '{print $2}')
            printf "  %-20s %s\n" "Mgmt interface:" "$mgmt_iface"
        elif [[ "$line" =~ ^[[:space:]]+Capability: ]]; then
            local cap status
            cap=$(echo "$line" | awk '{print $2}' | sed 's/,//')
            status=$(echo "$line" | grep -oP ', \K\w+' || echo "?")
            local status_color
            if [[ "$status" == "on" ]]; then status_color="$GR"; else status_color="$BR"; fi
            printf "  %-20s ${status_color}%s: %s${R}\n" "Capability:" "$cap" "$status"
        elif [[ "$line" =~ ^[[:space:]]+PortID: ]]; then
            local port_id
            port_id=$(echo "$line" | awk '{print $2, $3}' | sed 's/mac //')
            printf "  %-20s %s\n" "Port ID:" "$port_id"
        elif [[ "$line" =~ ^[[:space:]]+PortDescr: ]]; then
            local port_descr
            port_descr=$(echo "$line" | sed 's/^[[:space:]]*PortDescr:[[:space:]]*//')
            printf "  %-20s %s\n" "Port description:" "$port_descr"
        elif [[ "$line" =~ ^[[:space:]]+TTL: ]]; then
            local ttl
            ttl=$(echo "$line" | awk '{print $2}')
            printf "  %-20s %s\n" "TTL:" "$ttl seconds"
        fi
    done <<< "$lldp_out"

    # Management IP accessibility check
    echo ""
    echo -e "  ${B}Management IP accessibility:${R}"
    local mgmt_ips
    mgmt_ips=$(echo "$lldp_out" | grep -oP 'MgmtIP:[[:space:]]+\K\S+' || true)
    for mip in $mgmt_ips; do
        local ping_out ping_ok ping_ms
        ping_out=$( (ping -c 2 -W 2 -q "$mip" 2>/dev/null || true) )
        if echo "$ping_out" | grep -q 'rtt min'; then
            ping_ok=yes
            ping_ms=$(echo "$ping_out" | grep -oP 'rtt min/avg/max/mdev = [\d.]+/[\d.]+/[\d.]+/[\d.]+' | awk -F'/' '{printf "%.1f", $5}')
        else
            ping_ok=no; ping_ms="?"
        fi
        if [[ "$ping_ok" == "yes" ]]; then
            color_check yes "$mip reachable (${ping_ms}ms)"
        else
            color_check no "$mip unreachable"
        fi
    done

    # Try to fetch the switch web interface (common management ports)
    if [[ -n "$mgmt_ips" ]]; then
        echo ""
        echo -e "  ${B}Web management check:${R}"
        for mip in $mgmt_ips; do
            for port in 80 443; do
                local http_code url
                if [[ $port -eq 443 ]]; then
                    url="https://$mip:$port"
                else
                    url="http://$mip:$port"
                fi
                http_code=$( (curl -sk -o /dev/null -w "%{http_code}" --max-time 3 "$url" 2>/dev/null || true) )
                if [[ -n "$http_code" && "$http_code" != "000" ]]; then
                    echo -e "    ${mip}:${port} → HTTP ${http_code}"
                    # Try to get the page title
                    local title
                    title=$( (curl -sk --max-time 3 "$url" 2>/dev/null || true) | grep -oiP '<title>\K[^<]*' | head -1 || true)
                    if [[ -n "$title" ]]; then
                        echo -e "      Title: ${title}"
                    fi
                fi
            done
        done

        # TR-064 / TR-069 query (FRITZ!Box and many routers expose device info via SOAP on port 49000)
        echo ""
        echo -e "  ${B}TR-064 / UPnP device query (port 49000):${R}"
        for mip in $mgmt_ips; do
            local tr64_desc
            tr64_desc=$( (curl -sk --max-time 3 "http://$mip:49000/tr64desc.xml" 2>/dev/null || true) )
            if [[ -n "$tr64_desc" ]] && echo "$tr64_desc" | grep -q 'root'; then
                echo -e "    ${GR}TR-064 available${R} at http://$mip:49000/tr64desc.xml"

                # Extract device info
                local friendly mfr model serial fw_ver
                friendly=$(echo "$tr64_desc" | grep -oP '<friendlyName>\K[^<]*' | head -1 || true)
                mfr=$(echo "$tr64_desc" | grep -oP '<manufacturer>\K[^<]*' | head -1 || true)
                model=$(echo "$tr64_desc" | grep -oP '<modelName>\K[^<]*' | head -1 || true)
                serial=$(echo "$tr64_desc" | grep -oP '<serialNumber>\K[^<]*' | head -1 || true)

                printf "    %-18s %s\n" "Friendly name:" "$friendly"
                printf "    %-18s %s\n" "Manufacturer:" "$mfr"
                printf "    %-18s %s\n" "Model:" "$model"
                printf "    %-18s %s\n" "Serial:" "$serial"

                # Try to get firmware version via SOAP
                local igd_desc
                igd_desc=$( (curl -sk --max-time 3 "http://$mip:49000/igddesc.xml" 2>/dev/null || true) )
                if [[ -n "$igd_desc" ]]; then
                    echo -e "    ${GR}IGD (UPnP) also available${R}"
                fi

                # Query upstream connection info via TR-064 SOAP
                # This gets the WAN connection type, external IP, etc.
                # Get external IP address via SOAP
                local ext_ip
                ext_ip=$( (curl -sk --max-time 3 -H 'Content-Type: text/xml; charset="utf-8"' \
                    -H 'SOAPAction: urn:dslforum-org:service:WANIPConnection:1#GetExternalIPAddress' \
                    -d '<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body><u:GetExternalIPAddress xmlns:u="urn:dslforum-org:service:WANIPConnection:1"></u:GetExternalIPAddress></s:Body></s:Envelope>' \
                    "http://$mip:49000/upnp/control/WANIPConn1" 2>/dev/null || true) \
                    | grep -oP '<NewExternalIPAddress>\K[^<]*' | head -1 || true)

                # Get link info
                local link_type link_status
                link_type=$( (curl -sk --max-time 3 -H 'Content-Type: text/xml; charset="utf-8"' \
                    -H 'SOAPAction: urn:dslforum-org:service:WANCommonInterfaceConfig:1#GetCommonLinkProperties' \
                    -d '<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body><u:GetCommonLinkProperties xmlns:u="urn:dslforum-org:service:WANCommonInterfaceConfig:1"></u:GetCommonLinkProperties></s:Body></s:Envelope>' \
                    "http://$mip:49000/upnp/control/WANCommonIFC1" 2>/dev/null || true) )
                local wan_type wan_max_up wan_max_down
                wan_type=$(echo "$link_type" | grep -oP '<NewWANAccessType>\K[^<]*' || true)
                wan_max_up=$(echo "$link_type" | grep -oP '<NewLayer1UpstreamMaxBitRate>\K[^<]*' || true)
                wan_max_down=$(echo "$link_type" | grep -oP '<NewLayer1DownstreamMaxBitRate>\K[^<]*' || true)

                # Only print the header if we have at least one piece of data
                if [[ -n "$ext_ip" || -n "$wan_type" || -n "$wan_max_up" || -n "$wan_max_down" ]]; then
                    echo ""
                    echo -e "  ${B}WAN/Upstream info (TR-064 SOAP):${R}"
                    if [[ -n "$ext_ip" ]]; then
                        printf "    %-18s ${BL}%s${R}\n" "External IP:" "$ext_ip"
                    fi
                    [[ -n "$wan_type" ]] && printf "    %-18s %s\n" "WAN access type:" "$wan_type"
                    [[ -n "$wan_max_up" ]] && printf "    %-18s %s\n" "Max upstream:" "$(awk "BEGIN{printf \"%.1f Mbps\", $wan_max_up/1000000}")"
                    [[ -n "$wan_max_down" ]] && printf "    %-18s %s\n" "Max downstream:" "$(awk "BEGIN{printf \"%.1f Mbps\", $wan_max_down/1000000}")"
                fi

                # Get total bytes sent/received
                local bytes_info
                bytes_info=$( (curl -sk --max-time 3 -H 'Content-Type: text/xml; charset="utf-8"' \
                    -H 'SOAPAction: urn:dslforum-org:service:WANCommonInterfaceConfig:1#GetTotalBytesSent' \
                    -d '<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body><u:GetTotalBytesSent xmlns:u="urn:dslforum-org:service:WANCommonInterfaceConfig:1"></u:GetTotalBytesSent></s:Body></s:Envelope>' \
                    "http://$mip:49000/upnp/control/WANCommonIFC1" 2>/dev/null || true) \
                    | grep -oP '<NewTotalBytesSent>\K[^<]*' | head -1 || true)
                local bytes_rcvd
                bytes_rcvd=$( (curl -sk --max-time 3 -H 'Content-Type: text/xml; charset="utf-8"' \
                    -H 'SOAPAction: urn:dslforum-org:service:WANCommonInterfaceConfig:1#GetTotalBytesReceived' \
                    -d '<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body><u:GetTotalBytesReceived xmlns:u="urn:dslforum-org:service:WANCommonInterfaceConfig:1"></u:GetTotalBytesReceived></s:Body></s:Envelope>' \
                    "http://$mip:49000/upnp/control/WANCommonIFC1" 2>/dev/null || true) \
                    | grep -oP '<NewTotalBytesReceived>\K[^<]*' | head -1 || true)
                if [[ -n "$bytes_info" ]]; then
                    printf "    %-18s %s\n" "Total bytes sent:" "$(human_bytes "$bytes_info")"
                fi
                if [[ -n "$bytes_rcvd" ]]; then
                    printf "    %-18s %s\n" "Total bytes recv:" "$(human_bytes "$bytes_rcvd")"
                fi
            else
                echo -e "    ${DIM}TR-064 not available on $mip${R}"
            fi
        done
    fi
}

# --- Firewall analysis (scan gateway for open/blocked ports) -------------
section_firewall-analysis() {
    header "GATEWAY FIREWALL / PORT SCAN"

    local default_gw
    default_gw=$(ip -4 route show default 2>/dev/null | awk '{print $3; exit}' || echo "")

    if [[ -z "$default_gw" ]]; then
        echo -e "  ${RD}No default gateway found${R}"
        return
    fi

    echo -e "  ${B}Gateway:${R} $default_gw"
    echo ""

    # Ping the gateway first
    local gw_ok
    gw_ok=$( (ping -c 1 -W 2 -q "$default_gw" >/dev/null 2>&1 && echo yes) || echo no)
    if [[ "$gw_ok" == "yes" ]]; then
        color_check yes "Gateway $default_gw is reachable"
    else
        color_check no "Gateway $default_gw is NOT reachable"
        echo -e "  ${DIM}Cannot port-scan an unreachable gateway${R}"
        return
    fi
    echo ""

    # Common ports to check on a router/firewall
    local ports=(
        20 21 22 23 25 53 80 110 111 119 123 135 137 138 139
        143 161 162 389 443 445 465 500 514 515 587 631 636
        873 902 912 993 995 1194 1433 1521 1723 1900 2049
        3000 3128 3306 3389 4443 5000 5222 5353 5432 5900
        5984 6379 8000 8080 8443 8888 9000 9090 10000 27017
    )

    echo -e "  ${B}Port scan (TCP connect — checking which ports are open on the gateway):${R}"
    echo ""
    printf "  %-8s %-8s %-15s %-12s %s\n" "PORT" "PROTO" "SERVICE" "STATUS" "NOTE"
    printf "  %-8s %-8s %-15s %-12s %s\n" "----" "-----" "-------" "------" "----"

    local open_count=0 closed_count=0 filtered_count=0

    for port in "${ports[@]}"; do
        local svc status_color status_str note
        svc=$(getent services "$port" 2>/dev/null | awk '{print $1}' || true)
        [[ -z "$svc" ]] && svc="-"

        # Use /dev/tcp for TCP connect test (bash built-in, no nc needed)
        local result
        result=$(timeout 2 bash -c "echo >/dev/tcp/$default_gw/$port" >/dev/null 2>&1 && echo "open" || echo "?")
        if [[ "$result" == "open" ]]; then
            status_color="$GR"
            status_str="OPEN"
            note=""
            open_count=$((open_count + 1))
        else
            # Distinguish closed (RST) vs filtered (timeout)
            local rc
            timeout 2 bash -c "echo >/dev/tcp/$default_gw/$port" >/dev/null 2>&1 || rc=$?
            rc=${rc:-0}
            if [[ $rc -eq 124 ]]; then
                status_color="$YE"
                status_str="FILTERED"
                note="timeout (firewall blocking?)"
                filtered_count=$((filtered_count + 1))
            else
                status_color="$BR"
                status_str="CLOSED"
                note="RST received"
                closed_count=$((closed_count + 1))
            fi
        fi

        printf "  %-8s %-8s %-15s ${status_color}%-12s${R} %s\n" "$port" "TCP" "$svc" "$status_str" "$note"
    done

    echo ""
    echo -e "  ${B}Summary:${R}"
    printf "  ${GR}%-12s %d${R}\n" "OPEN:" "$open_count"
    printf "  ${BR}%-12s %d${R}\n" "CLOSED:" "$closed_count"
    printf "  ${YE}%-12s %d${R}\n" "FILTERED:" "$filtered_count"
    echo ""

    # UDP port scan (less reliable — UDP is connectionless)
    echo -e "  ${B}Quick UDP port check (common router services):${R}"
    printf "  %-8s %-8s %-15s %-12s %s\n" "PORT" "PROTO" "SERVICE" "STATUS" "NOTE"
    printf "  %-8s %-8s %-15s %-12s %s\n" "----" "-----" "-------" "------" "----"

    local udp_ports=(53 67 68 69 123 137 138 161 162 500 514 1900 5353)
    for port in "${udp_ports[@]}"; do
        local svc
        svc=$(getent services "$port" 2>/dev/null | awk '{print $1}' || true)
        [[ -z "$svc" ]] && svc="-"
        # UDP scan: send nothing, just check if we get ICMP port unreachable
        local result rc2
        timeout 2 bash -c "echo >/dev/udp/$default_gw/$port" >/dev/null 2>&1 && result="open|filtered" || rc2=$?
        rc2=${rc2:-0}
        if [[ $rc2 -eq 124 ]]; then
            result="open|filtered"
        else
            result="closed|filtered"
        fi
        local status_color
        if [[ "$result" == "open|filtered" ]]; then
            status_color="$YE"
        else
            status_color="$BR"
        fi
        printf "  %-8s %-8s %-15s ${status_color}%-12s${R} %s\n" "$port" "UDP" "$svc" "$result" "UDP is unreliable"
    done

    # If nmap is available, suggest it for a more thorough scan
    echo ""
    if command -v nmap &>/dev/null; then
        echo -e "  ${DIM}For a more thorough scan: nmap -sS -sU -p- $default_gw${R}"
    else
        echo -e "  ${DIM}Install nmap for a more thorough scan${R}"
    fi

    # Also show what services are on the gateway (try to grab banners)
    echo ""
    echo -e "  ${B}Service banners (for open HTTP/HTTPS ports):${R}"
    for port in 80 443; do
        local url result
        if [[ $port -eq 443 ]]; then
            url="https://$default_gw:$port"
        else
            url="http://$default_gw:$port"
        fi
        result=$( (curl -sk -o /dev/null -w "%{http_code}" --max-time 3 "$url" 2>/dev/null || true) )
        if [[ -n "$result" && "$result" != "000" ]]; then
            echo -e "    ${url} → HTTP ${result}"
            # Try to get the title
            local title
            title=$( (curl -sk --max-time 3 "$url" 2>/dev/null || true) | grep -oiP '<title>\K[^<]*' | head -1 || true)
            if [[ -n "$title" ]]; then
                echo -e "      Title: ${title}"
            fi
        fi
    done
}

# --- Network discovery (ping sweep local subnet) --------------------------
section_discovery() {
    header "NETWORK DISCOVERY (local subnet ping sweep)"

    local default_iface default_ip default_gw subnet
    default_iface=$(ip -4 route show default 2>/dev/null | awk '{print $5; exit}' || echo "")
    default_ip=$(ip -4 -br addr show "$default_iface" 2>/dev/null | awk '{print $3}' || echo "")
    default_gw=$(ip -4 route show default 2>/dev/null | awk '{print $3; exit}' || echo "")

    if [[ -z "$default_ip" ]]; then
        echo -e "  ${RD}No IPv4 address on default interface${R}"
        return
    fi

    # Extract subnet (e.g., 192.168.178.0/24)
    subnet=$(echo "$default_ip" | awk -F'/' '{print $1 "/" $2}')
    local net_base net_mask
    net_base=$(echo "$default_ip" | cut -d/ -f1)
    net_mask=$(echo "$default_ip" | cut -d/ -f2)

    echo -e "  ${B}Scanning subnet:${R} ${subnet}"
    echo -e "  ${B}Interface:${R} ${default_iface}"
    echo -e "  ${B}Gateway:${R} ${default_gw}"
    echo ""

    # Quick ping sweep (0.5s per host, parallel batch)
    echo -e "  ${DIM}Running ping sweep (this may take a few seconds)...${R}"
    echo ""

    local alive_count=0
    local net_prefix
    # Get the first 3 octets for /24 networks (most common home networks)
    if [[ "$net_mask" == "24" ]]; then
        net_prefix=$(echo "$net_base" | cut -d. -f1-3)

        printf "  %-18s %-20s %-8s %-12s %s\n" "IP ADDRESS" "HOSTNAME" "LATENCY" "MAC" "SOURCE"
        printf "  %-18s %-20s %-8s %-12s %s\n" "----------" "--------" "-------" "----" "------"

        # Ping sweep in parallel (background pings, collect results)
        local tmpdir
        tmpdir=$(mktemp -d)
        for i in $(seq 1 254); do
            local ip="${net_prefix}.${i}"
            (
                local result
                result=$( (ping -c 1 -W 1 -q "$ip" 2>/dev/null || true) )
                if echo "$result" | grep -q 'rtt min'; then
                    local latency
                    latency=$(echo "$result" | grep -oP 'rtt min/avg/max/mdev = [\d.]+/[\d.]+/[\d.]+/[\d.]+' | awk -F'/' '{printf "%.1f", $5}')
                    echo "${ip}|${latency:-?}" > "$tmpdir/${i}.txt"
                fi
            ) &
            # Batch 50 at a time to avoid fork bombing
            [[ $((i % 50)) -eq 0 ]] && wait
        done
        wait

        # Collect results
        for i in $(seq 1 254); do
            if [[ -f "$tmpdir/${i}.txt" ]]; then
                local ip latency hostname mac source
                IFS='|' read -r ip latency < "$tmpdir/${i}.txt"
                # Reverse DNS
                hostname=$(dig +short +time=1 +tries=1 -x "$ip" 2>/dev/null | head -1 | sed 's/\.$//' || echo "")
                [[ -z "$hostname" ]] && hostname="-"
                # MAC from ARP table (first lladdr only)
                mac=$(ip neigh show "$ip" 2>/dev/null | grep -oP 'lladdr \K\S+' | head -1 || echo "-")
                [[ -z "$mac" ]] && mac="-"
                # Source (ARP = directly connected, etc.)
                source="ping"
                [[ "$mac" != "-" ]] && source="ARP+ping"

                # Color the gateway differently
                local ip_color="$BR"
                [[ "$ip" == "$default_gw" ]] && ip_color="$YE"

                printf "  ${ip_color}%-18s${R} %-20s %-8s %-12s %s\n" \
                    "$ip" "$(truncate_str "$hostname" 20)" "${latency}ms" "$mac" "$source"
                alive_count=$((alive_count + 1))
            fi
        done
        rm -rf "$tmpdir"
    else
        echo -e "  ${DIM}Subnet /${net_mask} — ping sweep only supported for /24 networks${R}"
        echo -e "  ${DIM}Listing ARP neighbors instead:${R}"
        echo ""
        printf "  %-18s %-20s %-8s %-12s %s\n" "IP ADDRESS" "HOSTNAME" "LATENCY" "MAC" "STATE"
        printf "  %-18s %-20s %-8s %-12s %s\n" "----------" "--------" "-------" "----" "-----"
        ip neigh show 2>/dev/null | while read -r ip rest; do
            local mac hostname state
            mac=$(echo "$rest" | grep -oP 'lladdr \K\S+' || echo "-")
            state=$(echo "$rest" | awk '{print $NF}')
            hostname=$(dig +short +time=1 +tries=1 -x "$ip" 2>/dev/null | head -1 | sed 's/\.$//' || echo "-")
            [[ -z "$hostname" ]] && hostname="-"
            [[ -z "$mac" ]] && mac="-"
            printf "  %-18s %-20s %-8s %-12s %s\n" "$ip" "$(truncate_str "$hostname" 20)" "-" "$mac" "$state"
        done
        alive_count=$(ip neigh show 2>/dev/null | wc -l)
    fi

    echo ""
    echo -e "  ${B}Discovered ${alive_count} live hosts on ${subnet}${R}"

    # Also show DHCP lease info (what the DHCP server told us)
    echo ""
    echo -e "  ${B}DHCP lease info:${R}"
    local lease_file
    for lease_file in \
        "/var/lib/NetworkManager/internal-"*"$default_iface"* \
        "/var/lib/dhcp/dhclient.$default_iface.leases" \
        "/var/lib/NetworkManager/*.lease"; do
        if [[ -f "$lease_file" ]]; then
            echo -e "  ${DIM}Lease file: $lease_file${R}"
            # Extract key DHCP options
            (grep -E 'lease-time|server-hostname|domain-name| routers| dhcp-server| name-servers| ntp-servers| interface-mtu| expiry' "$lease_file" 2>/dev/null || true) | head -20 | while read -r line; do
                echo "    $line"
            done
            break
        fi
    done

    # NM-specific DHCP info
    echo ""
    echo -e "  ${B}DHCP details (from NetworkManager):${R}"
    # Filter to only server-provided options, skip client-side requested_* options
    (nmcli -t -f DHCP4.OPTION,IP4.ADDRESS device show "$default_iface" 2>/dev/null || true) \
        | grep -vE 'requested_|^IP4\.ADDRESS' \
        | while IFS= read -r line; do
            echo "    $line"
        done
}

# --- Traceroute ------------------------------------------------------------
section_trace() {
    header "TRACEROUTE (path to internet)"
    if [[ "$TRACE" != "yes" ]]; then
        echo "  (skipped — --no-trace)"
        return
    fi

    local target="1.1.1.1"

    if command -v mtr &>/dev/null; then
        start_spinner "Running mtr to $target"
        local mtr_out
        mtr_out=$(mtr --report --report-cycles 10 "$target" 2>&1 || echo "(failed)")
        stop_spinner
        echo "$mtr_out" | sed 's/^/  /'
    elif command -v traceroute &>/dev/null; then
        start_spinner "Running traceroute to $target"
        local trace_out
        trace_out=$(traceroute -m 20 -w 2 -q 1 "$target" 2>&1 || echo "(failed)")
        stop_spinner
        echo "$trace_out" | sed 's/^/  /'
    else
        echo -e "  ${DIM}neither mtr nor traceroute found${R}"
    fi
}

# ---------------------------------------------------------------------------
# JSON output
# ---------------------------------------------------------------------------
json_output() {
    echo "{"
    echo "  \"timestamp\": \"$(date -Iseconds)\","
    echo "  \"hostname\": \"$(hostname)\","

    jval() {
        local key="$1"; shift
        local val
        val=$("$@" 2>/dev/null | head -50 | tr '\n' ' ' | sed 's/"/\\"/g; s/\t/\\t/g' || true)
        echo "  \"$key\": \"${val}\","
    }

    jval "nm_state" nmcli -t -f STATE general status
    jval "nm_connectivity" nmcli -t -f CONNECTIVITY general status
    jval "default_route_v4" ip -4 route show default
    jval "default_route_v6" ip -6 route show default
    jval "ipv4_addresses" ip -4 -br addr show
    jval "ipv6_addresses" ip -6 -br addr show
    jval "lldp_neighbors" lldpctl
    jval "listening_tcp" ss -tlnH
    jval "listening_udp" ss -ulnH
    jval "established_tcp" ss -tnH state established
    jval "arp_neighbors" ip neigh show
    jval "nft_tables" nft list tables
    jval "dns_servers" resolvectl dns
    jval "resolvectl_status" resolvectl status
    jval "rfkill" rfkill list
    jval "wifi_list" nmcli -t -f SSID,SIGNAL,SECURITY dev wifi list
    jval "nm_connections_active" nmcli -t connection show --active
    jval "interface_stats" ip -s link show
    jval "conntrack_count" conntrack -L
    jval "conntrack_max" cat /proc/sys/net/nf_conntrack_max
    jval "tcp_states" ss -tanH
    jval "multicast_groups" ip maddr show
    jval "sysctl_ip_forward" sysctl net.ipv4.ip_forward
    jval "sysctl_ipv6_disable" sysctl net.ipv6.conf.all.disable_ipv6
    jval "dmesg_network" dmesg -T

    if [[ "$PUBLIC" == "yes" ]]; then
        local pub
        pub=$(curl -s4 --max-time 5 https://ifconfig.me 2>/dev/null || echo "error")
        echo "  \"public_ipv4\": \"${pub}\","
    fi

    if [[ "$TRACE" == "yes" ]] && command -v mtr &>/dev/null; then
        local trace
        trace=$(mtr --report --report-cycles 5 -j 1.1.1.1 2>/dev/null || echo "error")
        echo "  \"traceroute\": \"$(echo "$trace" | tr '\n' ' ' | sed 's/"/\\"/g')\","
    fi

    local vpn_status="(none)"
    if command -v ivpn &>/dev/null; then
        vpn_status=$(ivpn status 2>/dev/null | tr '\n' ' ' || echo "error")
    fi
    echo "  \"vpn_status\": \"${vpn_status}\""
    echo "}"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
if [[ "$JSON" == "yes" ]]; then
    json_output
    exit 0
fi

if [[ -n "$SECTION" ]]; then
    func="section_${SECTION}"
    if declare -f "$func" &>/dev/null; then
        "$func"
    else
        echo "Unknown section: $SECTION" >&2
        echo "Available: ${SECTIONS[*]}" >&2
        exit 1
    fi
    exit 0
fi

# Full report
echo -e "${B}${MG}═══════════════════════════════════════════════════════════════${R}"
echo -e "${B}${MG}  NETWORK STATUS REPORT${R}"
echo -e "${B}${MG}  $(date '+%Y-%m-%d %H:%M:%S %Z')${R}"
echo -e "${B}${MG}═══════════════════════════════════════════════════════════════${R}"

# Determine which sections to run
if [[ "$COMPACT" == "yes" ]]; then
    RUN_SECTIONS=("${COMPACT_SECTIONS[@]}")
else
    RUN_SECTIONS=("${SECTIONS[@]}")
fi

for sec in "${RUN_SECTIONS[@]}"; do
    func="section_${sec}"
    if declare -f "$func" &>/dev/null; then
        "$func"
    fi
done

echo -e "${B}${GR}═══════════════════════════════════════════════════════════════${R}"
echo -e "${B}${GR}  REPORT COMPLETE — $(date '+%Y-%m-%d %H:%M:%S')${R}"
echo -e "${B}${GR}═══════════════════════════════════════════════════════════════${R}"