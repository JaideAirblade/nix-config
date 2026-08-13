# Temporary Python package test/metadata fixes.
# Remove once nixpkgs fixes the upstream packages.
final: prev: {
  # netexec creates its own Python 3.12 package scope and replaces existing
  # packageOverrides, so fix only the broken metadata checks in netexec's
  # resolved dependency list. This leaves the global Python scope—and the
  # Mnemosyne packages injected there—untouched.
  netexec = prev.netexec.overridePythonAttrs (old: {
    dependencies = map
      (
        dependency:
        if final.lib.elem (dependency.pname or "") [ "bloodhound-py" "pynfsclient" ] then
          dependency.overridePythonAttrs
            (_: {
              dontCheckPythonMetadata = true;
            })
        else
          dependency
      )
      old.dependencies;
  });

  python314 = prev.python314.override (old: {
    packageOverrides = final.lib.composeExtensions
      (old.packageOverrides or (_: _: { }))
      (_self: super: {
        stamina = super.stamina.overridePythonAttrs (_: {
          doCheck = false;
        });
        qscintilla-qt6 = super.qscintilla-qt6.overridePythonAttrs (_: {
          doCheck = false;
          pythonMetadataCheckPhase = "";
          pythonImportsCheck = [ ];
        });
        # mat2 0.15.0 fails tests/test_libmat2.py::TestCleaning::test_all_parametred
        # on the 'mp4' case — expected_meta["TimeScale"] mismatches the parsed value
        # (720000). The shipped mp4 fixture's MP4Box-generated TimeScale drifted from
        # what the test asserts; nixpkgs master is still broken. Skip checks; runtime
        # binary works fine.
        mat2 = super.mat2.overridePythonAttrs (_: {
          doCheck = false;
        });
      });
  });
}
