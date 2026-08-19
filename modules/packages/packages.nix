# System-wide base packages shared across all hosts.
#
# Only the truly universal CLI tools and terminals live here — anything
# host-specific (Discord, seanime, Geary, Betterbird, disk-recovery,
# network analysis tools, ...) lives in hosts/<name>/packages/ so each
# host pulls only what it actually wants.
#
# Per-user tools are intentionally NOT managed here — the user owns their
# dotfiles and per-user installs (no home-manager).
_:
{
  nixos.modules.common =
    { pkgs, ... }:

    {
      environment.systemPackages = with pkgs; [
        vim # editor of last resort
        wget
        curl
        git # flakes pulls deps via git; also useful as a user tool
        gh # GitHub CLI — `gh auth login`, `gh pr create`, etc.
        just # command runner for the Justfile (see ~/nixos/Justfile)
        ripgrep
        fd # modern find — ripgrep's sibling for filenames
        jq
        fzf
        file
        which
        tree
        btop # better htop
        nix-output-monitor # `nom` — richer `nix` output

        # Terminals — every host wants a terminal installed system-wide.
        ghostty

        # --- System inspection & debugging ---
        pciutils # lspci — inspect GPU/PCIe bus (complements usbutils)
        usbutils # lsusb — identify USB devices from CLI
        lm_sensors # `sensors` — CPU/GPU/mobo temperatures
        lsof # what process has this file/port open?
        strace # system call tracing — debugging Wine/Electron/etc
        dmidecode # hardware inventory — motherboard, RAM slots, BIOS version
        ncdu # disk usage analyzer (TUI) — find what ate your disk

        # --- Modern CLI utilities ---
        eza # modern ls replacement — used via shell aliases
        bat # cat with syntax highlighting
        delta # beautiful git diffs (set as diff pager in ~/.gitconfig)
        dust # modern du — visual disk usage tree
        procs # modern ps — cleaner process listing
        bottom # btm — system monitor (alternative to btop)
        xh # HTTPie alternative — nicer than curl for API testing

        # --- Python ---
        python3 # base Python interpreter — not bundled inside tool wrappers

        # --- Crypto & keys ---
        gnupg # GnuPG — key management (complements YubiKey/age setup)

        # --- OCR ---
        tesseract # OCR engine — extract text from images/scans

        # --- Media download ---
        gallery-dl # download images from galleries — complements yt-dlp

        # --- Dev workflow ---
        direnv # per-directory env vars — load nix shells, set vars per project
      ];

      # Firefox is enabled by default for all hosts. Hosts that don't want
      # Firefox (e.g. Luna-Server, which uses Helium as its primary browser
      # and doesn't need a second) opt out via the per-host config:
      #   programs.firefox.enable = lib.mkForce false;
      programs.firefox.enable = true;

      # NOTE: Previously used `gh auth git-credential` as a git credential helper
      # for HTTPS GitHub access. Now switched to SSH — the SSH key is deployed
      # via sops-nix (modules/secrets/secrets.nix) and git is configured to use
      # git@github.com: instead of https://github.com/.
    }
  ;
}
