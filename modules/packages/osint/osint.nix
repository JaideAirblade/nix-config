# OSINT (Open Source Intelligence) tools.
#
# FOCA (ElevenPaths) is Windows-only C#/.NET GUI abandonware (last updated
# Aug 2021) — not in nixpkgs, not portable. Its core workflow (search web for
# documents on a domain → download → extract metadata: author names, usernames,
# paths, software versions) is replicated here by:
#   - theHarvester  (find documents/emails/names on a domain)
#   - exiftool      (already in network-tools.nix — extract metadata from files)
#   - recon-ng      (modular framework with document metadata modules)
#
# Categories below:
#   1. People search — username/email enumeration across platforms
#   2. Breach & credential lookup
#   3. Domain/infrastructure recon — subdomain enum, DNS, certificates
#   4. Frameworks — multi-tool OSINT platforms
#   5. Specialized — GitHub OSINT, Google OSINT, device search
{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    # === 1. People search — username & email enumeration ===
    sherlock        # Search 300+ sites for a username
    maigret         # Aggressive username enumeration + PDF reports (300+ sites)
    holehe          # Check if an email is registered on 120+ sites
    socialscan      # Check email/username availability across platforms
    user-scanner    # Username scanner across platforms

    # === 2. Breach & credential lookup ===
    h8mail          # Email OSINT & password breach hunting

    # === 3. Domain/infrastructure recon ===
    theharvester    # Harvest emails, subdomains, names from public sources
    dnsrecon        # DNS reconnaissance — enumerate records, zonewalk, brute
    subfinder       # Passive subdomain discovery from multiple sources
    amass           # Attack surface mapping — subdomain enum + ASN mapping
    dnsx            # DNS toolkit — resolve, brute-force, reverse lookup
    asn             # ASN/IP range lookup — who owns what IP space

    # === 4. Frameworks ===
    recon-ng        # Full-featured web recon framework (modular, like Metasploit for OSINT)
    sn0int          # Semi-automatic OSINT framework & package manager
    # bbot           # Automated recon/scanning framework — broken dep in nixpkgs (cloudcheck)
    metabigor       # OSINT without API keys — IP, ASN, domain recon

    # === 5. Specialized ===
    octosuite       # GitHub OSINT framework — enumerate orgs, repos, users
    ghunt           # Google OSINT — investigate Google accounts from email/ID
    (python3.withPackages (ps: with ps; [
      shodan        # Shodan CLI — search internet-connected devices, cameras, servers
    ]))
    urx             # Extract URLs from OSINT archives (Wayback, CommonCrawl, etc.)
    bitcrook        # OSINT tool — multiple data sources
  ];
}