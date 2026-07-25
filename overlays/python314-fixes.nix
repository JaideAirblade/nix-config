# Python 3.14 package test/metadata fixes.
# Remove once nixpkgs fixes the upstream packages.
final: prev: {
  python314 = prev.python314.override (old: {
    packageOverrides = final.lib.composeExtensions
      (old.packageOverrides or (_: _: {}))
      (self: super: {
        stamina = super.stamina.overridePythonAttrs (_: {
          doCheck = false;
        });
        qscintilla-qt6 = super.qscintilla-qt6.overridePythonAttrs (_: {
          doCheck = false;
          pythonMetadataCheckPhase = "";
          pythonImportsCheck = [];
        });
      });
  });
}
