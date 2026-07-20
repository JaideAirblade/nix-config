# Import-only entry for the AI/agent module.
# Each tool lives in a sibling <name>.nix; add new ones to imports as needed.
{ ... }:

{
  imports = [
    ./hermes-agent.nix
    ./mnemosyne.nix
  ];
}