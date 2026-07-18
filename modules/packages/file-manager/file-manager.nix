# Graphical file managers.
{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    nautilus # GNOME Files
  ];
}