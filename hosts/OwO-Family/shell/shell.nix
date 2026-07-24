# Shell config overrides for OwO-Family.
{ lib, ... }:

{
  # Override rebuild alias to target this host
  programs.git.config.user = {
    name = lib.mkForce "JaideAirblade";
    email = lib.mkForce "mail@jaidechan.moe";
  };
}