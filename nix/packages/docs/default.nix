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
    mkdir -p $out/bin $out/share/docs
    cp -r site/* $out/share/docs/

    cat > $out/bin/docs << EOF
    #!/usr/bin/env bash
    exec ${pkgs.python3}/bin/python3 -m http.server -d "$out/share/docs" 8000
    EOF
    chmod +x $out/bin/docs
  '';

  meta = {
    mainProgram = "docs";
  };
}
