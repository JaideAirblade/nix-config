# Overlay: patch amneziawg kernel module for Linux 7.x compatibility.
#
# The `ipv6_stub` symbol was removed from the public kernel API in Linux 7.x.
# This overlay applies the fix from PR #185
# (amnezia-vpn/amneziawg-linux-kernel-module#185)
# which replaces `ipv6_stub->ipv6_dst_lookup_flow` with `ip6_dst_lookup_flow`.
#
# Remove this overlay once the PR is merged and nixpkgs is updated.
# https://github.com/amnezia-vpn/amneziawg-linux-kernel-module/pull/185
_final: prev: {
  # Override amneziawg in ALL linuxPackages variants by recursing through
  # the linuxPackages_XXX attributes that nixpkgs creates.
  # The kernel module derivation is the same across all kernel versions,
  # but each linuxPackages set has its own .amneziawg attribute.
  linuxPackages = prev.linuxPackages.extend (_lpFinal: lpPrev: {
    amneziawg = lpPrev.amneziawg.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [
        (prev.fetchpatch {
          url = "https://github.com/amnezia-vpn/amneziawg-linux-kernel-module/commit/60c1bd0105246bbd309e5148f1399ac41c8ffd9f.patch";
          hash = "sha256-foDqFTt2jy8V8SF3674iBniodzMrWTiMEtH/rdjzFj0=";
        })
        (prev.fetchpatch {
          url = "https://github.com/amnezia-vpn/amneziawg-linux-kernel-module/commit/40b04a8d43f1e24ed6e495a5a97c05883ab1d122.patch";
          hash = "sha256-gP20swVf5vddqEbkwmx0jsaPJsrQud8NvK6x+4jHtF8=";
        })
      ];
    });
  });
}