{ ... }: {
  systemd.tmpfiles.rules = [
    "d /var/lib/app-data/databases/postgres/data 0700 999 999 -"
  ];
}
