{ lib
, dockerTools
}:

# OmniRoute is shipped as an OCI image with no usable upstream Nix
# module. We pull a single content-addressed layer set via dockerTools
# and re-export it as a Nix store path; the NixOS module then runs
# the image as a sibling container under the existing docker daemon.
#
# Re-pull to bump:
# Re-pull to bump: run `sudo docker pull diegosouzapw/omniroute`,
# then run `sudo docker image ls --digests diegosouzapw/omniroute`,
# then update `imageDigest` below. Do NOT use the `:latest` tag
# here — `dockerTools.pullImage` requires a content digest for
# reproducibility, and the `:latest` reference is a moving
# target that breaks reproducibility between deploys.
dockerTools.pullImage {
  imageName = "diegosouzapw/omniroute";
  imageDigest = "sha256:92c768c56e2de32c51a0621ef182835018b00b288c9bb235c5c5e4514658c1a1";
  finalImageName = "diegosouzapw/omniroute";
  sha256 = "sha256-3XPJB5X12mJIXEzf36IskKcIyrAm3xHPrKA9KjSfUNI=";
}
