{
  lib,
  config,
  pkgs,
  ...
}:
let
  composeFile = "${./.}/docker-compose.yaml";
  sopsFile = ../../data/matrix.yaml;

  # Whether this host acts as matrix.snyssen.be towards the outside world. Off until
  # the Phase B cutover, and flipped back together with domains.main.
  #
  # The homeserver's identity is fixed: server_name is matrix.snyssen.be, baked into
  # every user and room ID, and Synapse refuses to start on a database whose users
  # belong to another one. So a restore test on this host runs *as* that server, with
  # prod's signing key — and anything it sent out would be taken for prod's own:
  #
  # - federation: events signed with the real key, forking rooms behind prod's back.
  #   Off here (an empty federation_domain_whitelist plus send_federation: false).
  # - push: notifications to the phones of everyone with a pusher. Off here.
  # - the bridges: they would log in to Discord, Signal, WhatsApp and Meta with prod's
  #   sessions from the imported databases, alongside prod's own bridges. Not started.
  # - maubot: its clients point at prod's public homeserver URL with real access
  #   tokens, so its bots would act on prod itself. Not started.
  #
  # Clients still work: Element, MAS and the client API all run under domains.main.
  live = false;

  # The fixed half of the identity, written literally into the config files (user ID
  # regexes, permissions, double-puppet keys) rather than tokenized: it can never
  # follow domains.main.
  serverName = "matrix.snyssen.be";

  secret = path: config.sops.placeholder."compose-stacks/matrix/${path}";
  dbPassword = name: config.sops.placeholder."compose-stacks/databases/postgres/passwords/${name}";

  # The files in ./config are prod's own, rendered by Ansible's template module from
  # the legacy role with each secret replaced by an @TOKEN@ and every public URL's
  # domain by @MAIN_DOMAIN@. Rendering them here substitutes those tokens back.
  bridges = [
    "discord"
    "signal"
    "whatsapp"
    "meta"
  ];
  tokens = {
    MAIN_DOMAIN = config.domains.main;
    DB_PASS = dbPassword "matrix";
    MAS_DB_PASS = dbPassword "matrix_mas";
    MAUBOT_DB_PASS = dbPassword "maubot";
    REGISTRATION_SHARED_SECRET = secret "synapse/registration_shared_secret";
    MACAROON_SECRET_KEY = secret "synapse/macaroon_secret_key";
    FORM_SECRET = secret "synapse/form_secret";
    MAS_SHARED_SECRET = secret "mas/shared_secret";
    MAS_ENCRYPTION_SECRET = secret "mas/encryption_secret";
    MAS_OIDC_CLIENTID = secret "mas/oidc/client_id";
    MAS_OIDC_CLIENTSECRET = secret "mas/oidc/client_secret";
    DOUBLEPUPPET_AS_TOKEN = secret "doublepuppet/as_token";
    DOUBLEPUPPET_HS_TOKEN = secret "doublepuppet/hs_token";
    DOUBLEPUPPET_SENDER_LOCALPART = secret "doublepuppet/sender_localpart";
    DISCORD_AVATAR_PROXY_KEY = secret "discord/avatar_proxy_key";
    MAUBOT_SHARED_SECRET = secret "maubot/shared_secret";
    MAUBOT_ADMIN_USER = secret "maubot/admin_user";
    # Plaintext, unlike prod's template, which bcrypt-hashed it: maubot hashes a
    # plaintext admin password itself on start and writes the hash back.
    MAUBOT_ADMIN_PASS = secret "maubot/admin_pass";
  }
  // lib.listToAttrs (
    lib.concatMap (
      bridge:
      let
        upper = lib.toUpper bridge;
      in
      [
        (lib.nameValuePair "${upper}_DB_PASS" (dbPassword "matrix_${bridge}"))
        (lib.nameValuePair "${upper}_AS_TOKEN" (secret "${bridge}/as_token"))
        (lib.nameValuePair "${upper}_HS_TOKEN" (secret "${bridge}/hs_token"))
        (lib.nameValuePair "${upper}_SENDER_LOCALPART" (secret "${bridge}/sender_localpart"))
        (lib.nameValuePair "${upper}_SHARED_SECRET" (secret "${bridge}/shared_secret"))
      ]
      ++ lib.optional (bridge != "discord") (
        lib.nameValuePair "${upper}_PICKLE_KEY" (secret "${bridge}/pickle_key")
      )
    ) bridges
  );

  # Fails the build on any token left unsubstituted, so a typo can't ship a literal
  # @TOKEN@ as a password.
  render =
    file:
    let
      text = lib.replaceStrings (map (k: "@${k}@") (lib.attrNames tokens)) (lib.attrValues tokens) (
        builtins.readFile file
      );
      left = lib.filter lib.isList (builtins.split "@[A-Z][A-Z0-9_]*@" text);
    in
    assert lib.assertMsg (left == [ ]) "matrix: unsubstituted token(s) in ${toString file}";
    text;

  # Appended to prod's homeserver.yaml while not live; see `live` above. An empty
  # federation_domain_whitelist is Synapse's documented way to deny federation with
  # every server; send_federation: false also stops the main process sending any.
  notLive = ''

    # --- apps restore-test mode (default.nix: live = false) ---
    federation_domain_whitelist: []
    send_federation: false
    push:
      enabled: false
  '';

  # uid 991 is Synapse's user in its image, 65532 MAS's (distroless `nonroot`).
  synapseFile = {
    uid = 991;
    gid = 991;
    mode = "0400";
  };
  masFile = {
    uid = 65532;
    gid = 65532;
    mode = "0400";
  };
  masKeys = [
    "one"
    "two"
    "three"
    "four"
  ];

  # mautrix and maubot images all run as uid 1337.
  writableConfigs =
    lib.concatMap (bridge: [
      {
        template = "matrix-${bridge}-config.yaml";
        dest = "/var/lib/app-data/matrix/${bridge}/config.yaml";
      }
      {
        template = "matrix-appservice-${bridge}.yaml";
        dest = "/var/lib/app-data/matrix/${bridge}/registration.yaml";
      }
    ]) bridges
    ++ [
      {
        template = "matrix-maubot-config.yaml";
        dest = "/var/lib/app-data/matrix/maubot/config.yaml";
      }
    ];

  logConfig = pkgs.writeText "matrix-synapse-log.config" (builtins.readFile ./config/log.config);
  elementConfig = pkgs.writeText "matrix-element-config.json" (render ./config/element-config.json);

  plainSecrets = [
    "synapse/registration_shared_secret"
    "synapse/macaroon_secret_key"
    "synapse/form_secret"
    "mas/shared_secret"
    "mas/encryption_secret"
    "mas/oidc/client_id"
    "mas/oidc/client_secret"
    "mas/oidc/client_secret_hash"
    "doublepuppet/as_token"
    "doublepuppet/hs_token"
    "doublepuppet/sender_localpart"
    "discord/avatar_proxy_key"
    "maubot/shared_secret"
    "maubot/admin_user"
    "maubot/admin_pass"
  ]
  ++ lib.concatMap (
    bridge:
    map (key: "${bridge}/${key}") (
      [
        "as_token"
        "hs_token"
        "sender_localpart"
        "shared_secret"
      ]
      ++ lib.optional (bridge != "discord") "pickle_key"
    )
  ) bridges;
  envContent = ''
    COMPOSE_PROFILES=${lib.optionalString live "live"}
    SYNAPSE_CONFIG_PATH=${config.sops.templates."matrix-homeserver.yaml".path}
    SYNAPSE_LOG_CONFIG_PATH=${logConfig}
    SYNAPSE_SIGNING_KEY_PATH=${config.sops.secrets."compose-stacks/matrix/synapse/signing_key".path}
    SYNAPSE_AS_DOUBLEPUPPET_PATH=${config.sops.templates."matrix-appservice-doublepuppet.yaml".path}
    MAS_CONFIG_PATH=${config.sops.templates."matrix-mas-config.yaml".path}
    ELEMENT_CONFIG_PATH=${elementConfig}
  ''
  + lib.concatMapStrings (
    bridge:
    "SYNAPSE_AS_${lib.toUpper bridge}_PATH=${
      config.sops.templates."matrix-appservice-${bridge}.yaml".path
    }\n"
  ) bridges
  + lib.concatMapStrings (
    key:
    "MAS_KEY_${lib.toUpper key}_PATH=${
      config.sops.secrets."compose-stacks/matrix/mas/keys/${key}".path
    }\n"
  ) masKeys;
in
{
  assertions = [
    {
      # The literal server name in ./config must be the one this stack declares.
      assertion = lib.hasInfix "server_name: \"${serverName}\"" (
        builtins.readFile ./config/homeserver.yaml
      );
      message = "matrix: config/homeserver.yaml does not declare server_name ${serverName}";
    }
  ];

  systemd.tmpfiles.rules = map (dir: "d /var/lib/app-data/matrix/${dir} 0750 1337 1337 -") (
    bridges ++ [ "maubot" ]
  );

  # Every value carried over unchanged from the legacy vault, the signing and MAS keys
  # from the role's own vault-encrypted files (`sops-from-vault --file`). They have to
  # be prod's: the signing key *is* the server's identity, the MAS keys sign its tokens,
  # and the appservice tokens are what Synapse and each bridge recognise each other by.
  sops.secrets =
    lib.genAttrs (map (p: "compose-stacks/matrix/${p}") plainSecrets) (_: {
      inherit sopsFile;
    })
    // {
      "compose-stacks/matrix/synapse/signing_key" = synapseFile // {
        inherit sopsFile;
      };
    }
    // lib.listToAttrs (
      map (
        key:
        lib.nameValuePair "compose-stacks/matrix/mas/keys/${key}" (
          masFile
          // {
            inherit sopsFile;
          }
        )
      ) masKeys
    );

  sops.templates = {
    "matrix-homeserver.yaml" = synapseFile // {
      content = render ./config/homeserver.yaml + lib.optionalString (!live) notLive;
    };
    "matrix-appservice-doublepuppet.yaml" = synapseFile // {
      content = render ./config/doublepuppet-registration.yaml;
    };
    "matrix-mas-config.yaml" = masFile // {
      content = render ./config/mas-config.yaml;
    };
    # Root-only: matrix-config below installs copies the containers can read.
    "matrix-maubot-config.yaml".content = render ./config/maubot-config.yaml;
  }
  // lib.listToAttrs (
    lib.concatMap (bridge: [
      # Mounted into Synapse as is, and copied into the bridge's own /data.
      (lib.nameValuePair "matrix-appservice-${bridge}.yaml" (
        synapseFile
        // {
          content = render ./config/${bridge}-registration.yaml;
        }
      ))
      (lib.nameValuePair "matrix-${bridge}-config.yaml" {
        content = render ./config/${bridge}-config.yaml;
      })
    ]) bridges
  )
  // {
    "compose-matrix.env".content = envContent;
  };

  # As on prod: the client and federation APIs on matrix.<domain>, except the login,
  # logout and refresh endpoints, which MAS answers (its documented compatibility
  # layer; the longer rule wins on Traefik's default priority). maubot's admin UI is
  # LAN/tailnet-only, through monitoring's lan-whitelist middleware.
  reverseProxy.dynamicConfig.matrix = ''
    http:
      routers:
        synapse:
          rule: "Host(`matrix.${config.domains.main}`)"
          entryPoints:
            - websecure
          service: synapse
          tls:
            certResolver: le_main
        matrix-mas:
          rule: "Host(`matrix-mas.${config.domains.main}`) || (Host(`matrix.${config.domains.main}`) && PathRegexp(`^/_matrix/client/(.*)/(login|logout|refresh)`))"
          entryPoints:
            - websecure
          service: matrix-mas
          tls:
            certResolver: le_main
        element:
          rule: "Host(`element.${config.domains.main}`)"
          entryPoints:
            - websecure
          service: element
          tls:
            certResolver: le_main
        maubot:
          rule: "Host(`maubot.${config.domains.main}`)"
          entryPoints:
            - websecure
          service: maubot
          middlewares:
            - lan-whitelist
          tls:
            certResolver: le_main
      services:
        synapse:
          loadBalancer:
            servers:
              - url: "http://synapse:8008"
        matrix-mas:
          loadBalancer:
            servers:
              - url: "http://matrix_mas:8080"
        element:
          loadBalancer:
            servers:
              - url: "http://element:80"
        maubot:
          loadBalancer:
            servers:
              - url: "http://maubot:29316"
  '';

  compose-stacks.stacks.matrix = {
    restartTriggers = [
      ../../data/matrix.yaml
      ../../data/databases.yaml
      config.sops.templates."compose-matrix.env".content
    ]
    ++ map (t: config.sops.templates.${t}.content) (
      [
        "matrix-homeserver.yaml"
        "matrix-appservice-doublepuppet.yaml"
        "matrix-mas-config.yaml"
      ]
      ++ map (bridge: "matrix-appservice-${bridge}.yaml") bridges
    )
    ++ map (c: config.sops.templates.${c.template}.content) writableConfigs;
    inherit composeFile;
    environmentFile = config.sops.templates."compose-matrix.env".path;
    dockerNetworks = [
      "web"
      "db"
    ];
    extraAfter = [
      "mnt-bulk.mount"
      "reverse-proxy-dynamic-config.service"
      "matrix-storage-dirs.service"
      "matrix-config.service"
    ];
  };

  # Same shape as the other stacks' storage-dirs units: /mnt/bulk subpaths can't go
  # through ordinary tmpfiles rules, which run before the NFS mount is up.
  systemd.services.matrix-storage-dirs = {
    description = "Create /mnt/bulk directories the matrix stack expects";
    after = [ "mnt-bulk.mount" ];
    requires = [ "mnt-bulk.mount" ];
    before = [ "compose-matrix.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "matrix-storage-dirs" ''
        set -euo pipefail
        install -d -m 0750 -o 991 -g 991 /mnt/bulk/matrix/synapse/media_store
      '';
    };
  };

  # Installs the bridges' and maubot's rendered configs into their data directories:
  # their entrypoints edit config.yaml in place, so it must be a real, writable file
  # (see docker-compose.yaml). Same pattern as nextcloud-config. Reinstalled on every
  # change, which also resets maubot's admin password line to plaintext — maubot hashes
  # it again on its next start.
  systemd.services.matrix-config = {
    description = "Install the matrix bridges' and maubot's configs";
    restartTriggers = [
      ../../data/matrix.yaml
      ../../data/databases.yaml
    ]
    ++ map (c: config.sops.templates.${c.template}.content) writableConfigs;
    before = [ "compose-matrix.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "matrix-config" (
        ''
          set -euo pipefail
        ''
        + lib.concatMapStrings (c: ''
          install -m 0600 -o 1337 -g 1337 ${config.sops.templates.${c.template}.path} ${c.dest}
        '') writableConfigs
      );
    };
  };
}
