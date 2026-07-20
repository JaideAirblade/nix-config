# UPower — power device monitoring (battery status via D-Bus)
# Required by DMS for battery detection/widgets
{...}: {
  services.upower = {
    enable = true;
    percentageLow = 20;
    percentageCritical = 5;
    percentageAction = 2;
    criticalPowerAction = "HybridSleep";
  };
}