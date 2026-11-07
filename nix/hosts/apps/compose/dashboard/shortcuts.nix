# The launcher's shortcut tree, carried over verbatim from the legacy
# `dashboard__shortcuts` (ansible/hosts/group_vars/apps/vars.yml). URLs are deliberately
# left hardcoded rather than derived from config.domains.main: this is a launcher for the
# whole fleet — prod, the test VM (see "Apps (test VM)") and outside services alike — so
# rewriting them to the test domain would only point at things that don't exist there.
#
# Rendered to JSON in default.nix; webb-launcher reads it with js-yaml, and JSON is YAML.
[
  {
    children = [
      {
        children = [
          {
            name = "GitHub";
            url = "https://github.com";
          }
          {
            name = "Argunix";
            url = "https://argunix.snyssen.be";
          }
        ];
        name = "Development";
      }
      {
        name = "Dawarich";
        url = "https://location.snyssen.be";
      }
      {
        name = "PDF tools";
        url = "https://pdf.snyssen.be";
      }
      {
        name = "Recipes";
        url = "https://recipes.snyssen.be";
      }
      {
        name = "Actual";
        url = "https://actual.snyssen.be";
      }
      {
        children = [
          {
            name = "Matrix (Element)";
            url = "https://element.snyssen.be";
          }
          {
            name = "Matrix (Cinny)";
            url = "https://app.cinny.in";
          }
          {
            name = "Rallly";
            url = "https://events.bigdouf.team";
          }
          {
            name = "Sharkey";
            url = "https://social.snyssen.be";
          }
        ];
        name = "Social";
      }
    ];
    icon_classes = "las la-tools";
    name = "Work & Tools";
  }
  {
    children = [
      {
        children = [
          {
            name = "Personal website";
            url = "https://snyssen.be";
          }
          {
            name = "Bigdouf'site";
            url = "https://bigdouf.team";
          }
        ];
        name = "websites";
      }
      {
        children = [
          {
            name = "Nextcloud";
            url = "https://cloud.snyssen.be";
          }
          {
            name = "Syncthing";
            url = "https://sync.snyssen.be";
          }
          {
            name = "Syncthing (localhost)";
            url = "http://localhost:8384";
          }
          {
            name = "Paperless";
            url = "https://paperless.snyssen.be";
          }
        ];
        name = "Storage";
      }
      {
        children = [
          {
            name = "DnD - Saltmarsh";
            url = "https://dnd-saltmarsh.notes.snyssen.be";
          }
          {
            name = "DnD - Bahut";
            url = "https://dnd-bahut.notes.snyssen.be";
          }
          {
            name = "DnD - Yanwning Portal";
            url = "https://dnd-yp.notes.snyssen.be";
          }
          {
            name = "ME - En Eaux Troubles";
            url = "https://me-eet.notes.snyssen.be";
          }
        ];
        name = "Notes";
      }
    ];
    icon_classes = "las la-folder-open";
    name = "Documents";
  }
  {
    children = [
      {
        name = "Jellyfin";
        url = "https://streaming.snyssen.be";
      }
      {
        name = "Nebula";
        url = "https://nebula.tv";
      }
      {
        name = "Audiobooks";
        url = "https://audiobooks.snyssen.be";
      }
      {
        name = "Immich";
        url = "https://photos.snyssen.be";
      }
      {
        children = [
          {
            name = "Prowlarr";
            url = "https://prowlarr.snyssen.be";
          }
          {
            name = "Sonarr";
            url = "https://sonarr.snyssen.be";
          }
          {
            name = "Radarr";
            url = "https://Radarr.snyssen.be";
          }
          {
            name = "Lidarr";
            url = "https://lidarr.snyssen.be";
          }
          {
            name = "Bazarr";
            url = "https://bazarr.snyssen.be";
          }
          {
            name = "Torrents";
            url = "https://torrent.snyssen.be";
          }
          {
            name = "Usenet";
            url = "https://usenet.snyssen.be";
          }
          {
            name = "LidaTube";
            url = "https://lidatube.snyssen.be";
          }
          {
            name = "Lidify";
            url = "https://lidify.snyssen.be";
          }
        ];
        name = "Management";
      }
      {
        children = [
          {
            name = "Libro.fm";
            url = "https://libro.fm/";
          }
          {
            name = "Pinchflat";
            url = "https://yt.snyssen.be";
          }
        ];
        name = "Acquisition";
      }
    ];
    icon_classes = "las la-photo-video";
    name = "Media";
  }
  {
    children = [
      {
        name = "Home Assistant";
        url = "https://hass.snyssen.be";
      }
      {
        children = [
          {
            name = "technitium-primary";
            url = "https://technitium-primary.taild023c5.ts.net:53443/";
          }
          {
            name = "technitium-secondary";
            url = "https://technitium-secondary.taild023c5.ts.net:53443/";
          }
          {
            name = "Dynu";
            url = "https://www.dynu.com/en-US/ControlPanel";
          }
          {
            name = "Porkbun";
            url = "https://porkbun.com/account/login";
          }
        ];
        name = "DNS management";
      }
      {
        children = [
          {
            name = "Apps";
            url = "https://routing.snyssen.be";
          }
          {
            name = "Ingress";
            url = "https://ingress.snyssen.be";
          }
          {
            name = "Apps (test VM)";
            url = "https://routing.snyssen1.xyz";
          }
        ];
        name = "Reverse Proxies";
      }
      {
        children = [
          {
            name = "Router";
            url = "http://192.168.1.1";
          }
          {
            name = "Unifi controller";
            url = "http://unifi.snyssen.be";
          }
          {
            name = "Speedtest (with server)";
            url = "https://speedtest.snyssen.be";
          }
          {
            name = "Speedtest (outside)";
            url = "https://www.speedtest.net";
          }
          {
            name = "Speedtest tracker";
            url = "https://speedtest-tracker.snyssen.be";
          }
          {
            name = "Tailscale";
            url = "https://login.tailscale.com/admin/machines";
          }
        ];
        name = "Networking";
      }
      {
        children = [
          {
            name = "backrest";
            url = "https://backrest.snyssen.be";
          }
          {
            name = "LDAP";
            url = "https://ldap.snyssen.be";
          }
          {
            name = "pgadmin";
            url = "https://pgadmin.snyssen.be";
          }
          {
            name = "Crowdsec WebUI";
            url = "https://crowdsec-ui.snyssen.be";
          }
          {
            name = "Umami";
            url = "https://umami.snyssen.be";
          }
          {
            name = "Backblaze";
            url = "https://secure.backblaze.com/b2_buckets.htm";
          }
        ];
        name = "Tools";
      }
      {
        children = [
          {
            name = "Grafana";
            url = "https://monitor.snyssen.be";
          }
          {
            name = "Gatus";
            url = "https://uptime.snyssen.be";
          }
          {
            name = "Prometheus";
            url = "https://prometheus.snyssen.be";
          }
          {
            name = "Traefik";
            url = "https://routing.snyssen.be";
          }
          {
            name = "Healthchecks.io";
            url = "https://healthchecks.io/projects/b7456f9a-2422-4e2a-8b0f-96909b448f78/checks/";
          }
        ];
        name = "Monitoring";
      }
    ];
    icon_classes = "las la-server";
    name = "Infrastructure";
  }
  {
    children = [
      {
        children = [
          {
            name = "Foundry VTT";
            url = "https://dnd.snyssen.be";
          }
          {
            name = "Roll20";
            url = "https://roll20.net";
          }
          {
            name = "5e tools";
            url = "https://5e.tools";
          }
          {
            name = "HeroForge";
            url = "https://www.heroforge.com";
          }
          {
            name = "Token stamp";
            url = "https://rolladvantage.com/tokenstamp";
          }
          {
            name = "Fantasy name generator";
            url = "https://www.fantasynamegenerators.com";
          }
        ];
        name = "Tabletop RPG";
      }
      {
        name = "Minecraft live map";
        url = "https://mc.snyssen.be";
      }
      {
        name = "USW live map";
        url = "https://mc-usw.snyssen.be";
      }
      {
        name = "Icarus Terminal";
        url = "http://snyssen-windows.lan:3300";
      }
    ];
    icon_classes = "las la-gamepad";
    name = "Games";
  }
]
