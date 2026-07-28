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
      });
  });
}
