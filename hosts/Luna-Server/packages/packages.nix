# Luna-Server host-specific packages.
#
# A small list of GUI apps jaide wants when she uses this machine remotely
# (e.g. during the trip to the parents'). The rest of the package set
# comes from the shared modules imported by the entry point.
#
# The box is headless — no display server, no DM. The GUI binaries are
# available so they can be invoked via X-forwarding, `nix run`, or a remote
# desktop session if one is ever set up. They don't auto-start because
# nothing in the desktop session depends on them.

_:
{
  nixos.hosts."Luna-Server" =
    { pkgs, lib, ... }:

    {
      environment.systemPackages = with pkgs; [
        # Helium — private Chromium-based browser. Matches the desktop
        # experience on UwU/TSBW so the 1Password integration, profile, and
        # extensions are consistent across machines.
        helium-bin

        # Readest is provided by modules/theming/readest-dms-theme.nix as a
        # wrapped version with WEBKIT_INSPECTOR_HTTP_SERVER=127.0.0.1:9223

        # OfficeCLI — Office suite for AI agents (.docx/.xlsx/.pptx via CLI).
        # Single .NET binary, autoPatchelf'd for NixOS. Skill auto-installed
        # at ~/.hermes/skills/officecli/ by the upstream install script.
        officecli

        # Vesktop — Discord client with Vencord. The server is headless, but
        # jaide wants the same client as on UwU available for X-forwarding /
        # remote desktop sessions.
        vesktop

        # Octarine — private markdown note-taking app (custom package from pkgs/).
        # Same as on UwU and TSBW-W01800. Workspace at ~/Documents/Life/.
        octarine

        # Herm — modern TUI for Hermes Agent (custom package from pkgs/).
        # Built with OpenTUI + Bun. Provides chat, sessions, skills, cron,
        # kanban, analytics, and config management in one terminal interface.
        # Wrapped with NixOS-specific HERMES_PYTHON and HERMES_AGENT_ROOT
        # so herm can find and spawn the tui_gateway subprocess from the
        # nix store instead of looking for ~/.hermes/hermes-agent/venv/.
        (symlinkJoin {
          name = "herm";
          paths = [ herm-tui ];
          buildInputs = [ makeWrapper ];
          postBuild = ''
            wrapProgram $out/bin/herm \
              --set HERMES_PYTHON ${lib.getExe' hermes-agent.hermesVenv "python3"} \
              --set HERMES_AGENT_ROOT ${hermes-agent.hermesVenv}/lib/python3.12/site-packages
          '';
        })
      ];

      # Opt out of the shared Firefox enable (modules/packages/packages.nix).
      # Luna-Server uses Helium as its primary browser; no second browser.
      programs.firefox.enable = lib.mkForce false;
    }
  ;
}
