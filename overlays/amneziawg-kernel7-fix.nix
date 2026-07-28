# Overlay: patch amneziawg kernel module for Linux 7.x compatibility.
#
# The `ipv6_stub` symbol was removed from the public kernel API in Linux 7.x.
# This overlay applies the fix from PR #185
# (amnezia-vpn/amneziawg-linux-kernel-module#185)
# which replaces `ipv6_stub->ipv6_dst_lookup_flow` with `ip6_dst_lookup_flow`.
#
# We patch all linuxPackages variants that hosts might use.
#
# Remove this overlay once the PR is merged and nixpkgs is updated.
# https://github.com/amnezia-vpn/amneziawg-linux-kernel-module/pull/185
_final: prev:
let
  patchAmneziawg = pkg:
    pkg.overrideAttrs (_old: {
      patches = [ ];
      postPatch = ''
        # socket.h: add forward declarations for kernel 7.x
        # -p2 strips a/src/ → socket.h (sourceRoot is src/)
        patch -p2 < ${prev.fetchurl {
          url = "https://github.com/amnezia-vpn/amneziawg-linux-kernel-module/commit/60c1bd0105246bbd309e5148f1399ac41c8ffd9f.patch";
          hash = "sha256-foDqFTt2jy8V8SF3674iBniodzMrWTiMEtH/rdjzFj0=";
        }}
        # socket.c: replace ipv6_stub with ip6_dst_lookup_flow
        patch -p2 < ${prev.fetchurl {
          url = "https://github.com/amnezia-vpn/amneziawg-linux-kernel-module/commit/40b04a8d43f1e24ed6e495a5a97c05883ab1d122.patch";
          hash = "sha256-gP20swVf5vddqEbkwmx0jsaPJsrQud8NvK6x+4jHtF8=";
        }}
      '';
    });
in
{
  linuxPackages = prev.linuxPackages.extend (_kpFinal: kpPrev: {
    amneziawg = patchAmneziawg kpPrev.amneziawg;
  });
  linuxPackages_latest = prev.linuxPackages_latest.extend (_kpFinal: kpPrev: {
    amneziawg = patchAmneziawg kpPrev.amneziawg;
  });
}
