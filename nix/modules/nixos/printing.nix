{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.printing;
in
{
  options.printing = {
    enable = lib.mkEnableOption "printing support" // {
      default = true;
    };

    scanner = {
      enable = lib.mkEnableOption "scanner support with scanservjs";

      paperless = {
        enable = lib.mkEnableOption "automatic upload to Paperless-ngx after scanning";

        url = lib.mkOption {
          type = lib.types.str;
          example = "https://paperless.snyssen.be";
          description = "Paperless-ngx instance URL (without trailing slash)";
          default = "https://paperless.snyssen.be";
        };

        apiTokenPath = lib.mkOption {
          type = lib.types.path;
          description = ''
            Path to file containing the Paperless API token.
            Should be provided using a SOPS secret.
          '';
          example = "config.sops.secrets.\"paperless/api-token\".path";
        };
      };
    };
  };

  config = lib.mkMerge [
    # Basic printing configuration
    (lib.mkIf cfg.enable {
      services.printing.enable = true;
      services.printing.drivers = [ pkgs.hplip ];
      hardware.sane.enable = true;
      hardware.sane.extraBackends = [ pkgs.hplipWithPlugin ];
    })

    # Scanner configuration with scanservjs
    (lib.mkIf cfg.scanner.enable {
      services.scanservjs.enable = true;
    })

    # Paperless integration
    (lib.mkIf cfg.scanner.paperless.enable (
      let
        paperlessUploadScript = pkgs.writeShellApplication {
          name = "paperless-upload";
          runtimeInputs = [
            pkgs.curl
            pkgs.coreutils
          ];
          text = ''
            set -euo pipefail

            if [ $# -ne 1 ]; then
              echo "Usage: $0 <file-path>" >&2
              exit 1
            fi

            FILE="$1"

            if [ ! -f "$FILE" ]; then
              echo "Error: File '$FILE' does not exist" >&2
              exit 1
            fi

            if [ ! -f "${cfg.scanner.paperless.apiTokenPath}" ]; then
              echo "Error: API token file not found at ${cfg.scanner.paperless.apiTokenPath}" >&2
              exit 1
            fi

            TOKEN=$(cat "${cfg.scanner.paperless.apiTokenPath}")

            echo "Uploading $FILE to Paperless at ${cfg.scanner.paperless.url}..."

            if curl -X POST \
              -H "Authorization: Token $TOKEN" \
              -F "document=@$FILE" \
              "${cfg.scanner.paperless.url}/api/documents/post_document/" \
              --fail --silent --show-error --max-time 30; then
              echo "Successfully uploaded $FILE to Paperless"
              exit 0
            else
              echo "Failed to upload $FILE to Paperless" >&2
              exit 1
            fi
          '';
        };
      in
      {
        services.scanservjs.extraActions = [
          ''
            {
              name: 'Upload to Paperless',
              async execute(fileInfo) {
                const Process = require("${pkgs.scanservjs}/lib/node_modules/scanservjs-api/src/classes/process");
                return await Process.spawn('${paperlessUploadScript}/bin/paperless-upload "' + fileInfo.fullname + '"');
              }
            }
          ''
        ];

        # Make the upload script available for manual use
        environment.systemPackages = [ paperlessUploadScript ];
      }
    ))
  ];
}
