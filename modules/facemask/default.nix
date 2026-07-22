# Import-only entry for the facemask module.
# Owns the v4l2loopback kernel module (virtual camera device) and
# system-level deps for real-time face swap tools (Deep-Live-Cam, etc.).
{ ... }:

{
  imports = [
    ./facemask.nix
  ];
}