# The overlay function that injects mnemosyne into hermes-agent's venv.
#
# Imported by hermes-agent.nix so it composes AFTER the upstream overlay
# (which unconditionally sets `hermes-agent = upstream pkg`). Running second
# lets us chain `.override { extraPythonPackages = ... }` on the upstream
# package and have the result survive.
#
# We build mnemosyne WITHOUT the [embeddings] extra (fastembed + sqlite-vec)
# because fastembed's closure collides with deps already in Hermes' sealed
# venv (huggingface-hub, numpy, onnxruntime, pillow, requests, tokenizers,
# tqdm — all present in Hermes). mnemosyne still works via FTS5 + keyword
# search; to enable vector search later, point MNEMOSYNE_EMBEDDING_API_URL
# at a remote OpenAI-compatible endpoint (no local deps needed).
#
# pyyaml is the only runtime dep mnemosyne declares, and it's already in
# Hermes' venv — so we don't propagate it (Hermes' collision check rejects
# dupes). It resolves at runtime from Hermes' sealed venv via PYTHONPATH.
final: prev:
let
  py = final.python312;

  mnemosyne-memory = py.pkgs.buildPythonPackage rec {
    pname = "mnemosyne-memory";
    version = "3.14.0";
    pyproject = true;
    nativeBuildInputs = with py.pkgs; [ setuptools wheel ];
    src = final.fetchurl {
      url = "https://files.pythonhosted.org/packages/c1/b1/a3b8a18828aadd4fc7e67fb262294ea0038dbf130c8aac23196e998542d7/mnemosyne_memory-3.14.0.tar.gz";
      sha256 = "1106e5ec69ac2249dcaded1b7a948d8f5ceec7959a3176cc6efbdd0fa41276eb";
    };
    # pyyaml is in Hermes' sealed venv; don't propagate (collision check).
    # Disable the wheel's runtime-deps + import checks — they'd reject the
    # missing pyyaml, but it resolves at runtime from Hermes' venv.
    dontCheckRuntimeDeps = true;
    pythonImportsCheck = [ ];
    doCheck = false;
    meta = with final.lib; {
      description = "Zero-dependency AI memory. SQLite-backed.";
      homepage = "https://github.com/mnemosyne-oss/mnemosyne";
      license = licenses.mit;
      platforms = platforms.linux;
    };
  };

  mnemosyne-hermes = py.pkgs.buildPythonPackage rec {
    pname = "mnemosyne-hermes";
    version = "0.4.0";
    pyproject = true;
    nativeBuildInputs = with py.pkgs; [ setuptools wheel ];
    src = final.fetchurl {
      url = "https://files.pythonhosted.org/packages/45/da/77d0f0cb636b896f1c23449541a0d6a9e3a5301a6dee7a2064082a4d8583/mnemosyne_hermes-0.4.0.tar.gz";
      sha256 = "7e487e70d5572095ce403c5ff19431412060a7ef56c87fc4456da499b0474eb8";
    };
    propagatedBuildInputs = with py.pkgs; [ mnemosyne-memory ];
    dontCheckRuntimeDeps = true;
    pythonImportsCheck = [ ];
    doCheck = false;
    meta = with final.lib; {
      description = "Mnemosyne memory provider for Hermes Agent";
      homepage = "https://github.com/mnemosyne-oss/mnemosyne";
      license = licenses.mit;
      platforms = platforms.linux;
    };
  };
in
{
  python312 = prev.python312 // {
    pkgs = prev.python312.pkgs // { inherit mnemosyne-memory mnemosyne-hermes; };
  };
  hermes-agent = prev.hermes-agent.override {
    extraPythonPackages = [ mnemosyne-hermes ];
  };
}