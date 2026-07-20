# Google Drive sync via rclone.
#
# Bidirectionally syncs ~/Documents/Life with a Google Drive folder every 5
# minutes via a systemd user timer. rclone is installed system-wide; the
# remote config (~/.config/rclone/rclone.conf) is user-owned and NOT managed
# by Nix.
#
# IMPORTANT: the rclone remote's root_folder_id points directly at the Life
# vault folder in Drive, so the remote path is `gdrive:` (root), NOT
# `gdrive:Life`. Using a `Life` subpath would create a nested folder inside
# the vault — or worse, `rclone sync` from an empty local dir to the vault
# root would DELETE the entire remote vault. Never use one-way `sync` here
# with an empty source.
#
# SETUP (run once, imperatively, after deploying this config):
#   1. Run `rclone config`
#   2. Choose "n" for new remote, name it "gdrive"
#   3. Choose "drive" (Google Drive)
#   4. Follow the OAuth flow (opens browser, grant access)
#   5. For "root_folder_id", paste the Google Drive folder ID from the URL
#      (the part after /folders/ in the Drive URL)
#   6. Leave scope as default (1 - full access)
#   7. Finish and test with: rclone ls gdrive:
#
# First run after setup (initializes bisync state, pulls remote -> local):
#   rclone bisync --resync --verbose ~/Documents/Life gdrive:
# The timer starts on boot (5min delay) and runs every 5min after.
# Manual sync: rclone bisync --verbose ~/Documents/Life gdrive:
{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    rclone
  ];

  # systemd user services for rclone Google Drive sync
  systemd.user.services.rclone-gdrive-sync = {
    description = "Rclone Google Drive sync";
    serviceConfig = {
      Type = "oneshot";
      # Bidirectionally sync ~/Documents/Life with the vault root on Drive.
      # bisync keeps a listing state in ~/.cache/rclone/bisync; both sides
      # are reconciled on every run (deletions propagate both ways).
      ExecStart = "${pkgs.rclone}/bin/rclone bisync --verbose --transfers 4 %h/Documents/Life gdrive:";
    };
  };

  systemd.user.timers.rclone-gdrive-sync = {
    description = "Timer for Rclone Google Drive sync";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "5min";
    };
  };
}