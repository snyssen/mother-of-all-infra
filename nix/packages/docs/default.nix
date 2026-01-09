{
  pkgs,
  perSystem,
  ...
}:
pkgs.stdenvNoCC.mkDerivation {
  name = "docs";

  unpackPhase = ''
    cp ${../../../mkdocs.yaml} mkdocs.yaml
    cp -r ${../../../docs} docs
  '';

  nativeBuildInputs = with pkgs.python3Packages; [
    mike
    mkdocs
    mkdocs-material
    mkdocs-awesome-nav
  ];

  buildPhase = ''
    mkdocs build
  '';

  installPhase = ''
    mv site $out
  '';
}
