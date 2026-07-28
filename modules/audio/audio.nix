# Sound via PipeWire.
#
# The base PipeWire config is shared. Device-specific WirePlumber policy is
# contributed to the UwU-only personal role.
_:
{
  nixos.modules.common =
    _:

    {
      services.pulseaudio.enable = false;
      security.rtkit.enable = true;
      services.pipewire = {
        enable = true;
        alsa.enable = true;
        alsa.support32Bit = true;
        pulse.enable = true;
        # jack.enable = true;
      };
    }
  ;

  nixos.modules.personal =
    { lib, ... }:

    {
      services.pipewire = {

        # Pin the fifine USB audio card to the analog-stereo + mono-input profile.
        # Without this, WirePlumber auto-selects the iec958 (digital) profile, which
        # routes playback to the S/PDIF port instead of the headphone jack, so the
        # DT 770 Pro hears nothing.
        wireplumber.extraConfig."10-fifine-analog-profile" = lib.mkDefault {
          "monitor.alsa.rules" = [
            {
              matches = [
                { "device.name" = "~alsa_card.usb-MV-SILICON_fifine_Chat_20190808-00"; }
              ];
              actions.update-props = {
                "device.profile" = "output:analog-stereo+input:mono-fallback";
                "api.acp.auto-profile" = false;
                "api.acp.auto-port" = false;
              };
            }
          ];
        };

        # NVIDIA HDMI audio: the monitor is on DisplayPort (DP-1), which maps to
        # ALSA HDMI device 1 (profile output:hdmi-stereo-extra1). WirePlumber's
        # port-availability detection mis-reports NVIDIA DP ports as unavailable,
        # so it falls back to hdmi-stereo (HDMI 0, pin 0x4) which has nothing
        # attached. Pin the GA102 card to extra1 and force the port available.
        wireplumber.extraConfig."11-nvidia-dp-audio" = lib.mkDefault {
          "monitor.alsa.rules" = [
            {
              matches = [
                { "device.name" = "~alsa_card.pci-0000_0b_00.1"; }
              ];
              actions.update-props = {
                "device.profile" = "output:hdmi-stereo-extra1";
                "api.acp.auto-profile" = false;
                "api.acp.auto-port" = false;
              };
            }
            {
              matches = [
                { "node.name" = "~alsa_output.pci-0000_0b_00.1.hdmi-stereo-extra1"; }
              ];
              actions.update-props = {
                "node.disabled" = false;
              };
            }
          ];
        };
      };
    }
  ;
}
