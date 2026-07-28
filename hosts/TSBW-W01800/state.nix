# Host-specific state version. Leave this at the release the system was
# first installed with.
_:
{
  nixos.hosts."TSBW-W01800" =
    _:

    {
      system.stateVersion = "26.05";
    }
  ;
}
