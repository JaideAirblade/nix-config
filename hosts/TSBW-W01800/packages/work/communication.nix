# Work-related communication tools
{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    betterbird       # Thunderbird fork with bug fixes & refinements (custom package from pkgs/)
    teams-for-linux  # Unofficial Microsoft Teams client
  ];
}