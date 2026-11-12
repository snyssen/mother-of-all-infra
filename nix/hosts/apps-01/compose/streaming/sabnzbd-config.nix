{ config }:
# SABnzbd's sabnzbd.ini, as a sops template: the server credentials and the API/NZB keys
# are secrets. Copied into its /config before every start of the stack (see
# streaming-download-clients-config in default.nix), as the legacy Ansible role did, so
# this file is the source of truth and changes made in the web UI last only until then.
#
# The legacy role's template, trimmed to what differs from SABnzbd's defaults: it fills
# in every missing key itself, and writes the full file back on shutdown.
let
  secret = name: config.sops.placeholder."compose-stacks/streaming/usenet/${name}";
  host = secret "server/host";
in
''
  __version__ = 19
  __encoding__ = utf-8
  [misc]
  host = ::
  port = 8080
  url_base = /sabnzbd
  # Traefik is the only way in (Authelia-gated), and every request reaches SABnzbd from
  # Traefik's private address. verify_xff_header = 0 makes SABnzbd judge that address,
  # not the client's in X-Forwarded-For, which from the tailnet (100.64.0.0/10) or the
  # internet it would refuse as external.
  inet_exposure = 0
  verify_xff_header = 0
  local_ranges = ,
  host_whitelist = usenet.${config.domains.main},
  api_key = ${secret "api_key"}
  nzb_key = ${secret "nzb_key"}
  # TRaSH Guides layout (ansible/roles/container_streaming/README.md): the *arr apps see
  # the same /data/usenet, so a finished job's category folder is where they look.
  download_dir = /data/usenet/incomplete
  complete_dir = /data/usenet
  cache_limit = 492.5 M
  direct_unpack = 0
  history_retention = 0
  tv_categories = tv,
  movie_categories = movies,
  date_categories = tv,
  [servers]
  [[${host}]]
  name = ${host}
  displayname = ${host}
  host = ${host}
  port = ${secret "server/port"}
  timeout = 60
  username = ${secret "server/user"}
  password = ${secret "server/password"}
  connections = 8
  ssl = 1
  ssl_verify = 2
  enable = 1
  required = 0
  optional = 0
  retention = 0
  priority = 0
  [categories]
  [[*]]
  name = *
  order = 0
  pp = 3
  script = None
  dir = ""
  priority = 0
  [[movies]]
  name = movies
  order = 1
  pp = ""
  script = Default
  dir = ""
  priority = -100
  [[tv]]
  name = tv
  order = 2
  pp = ""
  script = Default
  dir = ""
  priority = -100
  [[music]]
  name = music
  order = 3
  pp = ""
  script = Default
  dir = ""
  priority = -100
  [[books]]
  name = books
  order = 4
  pp = ""
  script = Default
  dir = ""
  priority = -100
''
