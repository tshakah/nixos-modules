{functions, ...}: {
  name,
  lib,
  pkgs,
  config,
  options,
  ...
}: let
  serviceName = functions.toSnakeCase name;
  cfg = config.services."${serviceName}";
  opt = options.services."${serviceName}";
  dataDir = cfg.dataDir;
  user = cfg.user;

  nginxHost = {
    forceSSL = true;
    useACMEHost = "${cfg.host}";
    locations."/.well-known/".root = "/var/lib/acme/acme-challenge/";

    extraConfig = ''
      error_page 403 500 502 503 504 /50x.html;
      location = /50x.html {
        root ${dataDir}/nginx;
        internal;
      }

      location ~ \.php$ {
        return 404;
      }
    '';

    locations."~* ^.+\.(css|cur|gif|gz|ico|jpg|jpeg|js|png|svg|woff|woff2|webm)$" = {
      extraConfig = ''
        root ${dataDir}/static;
        etag off;
        expires max;
        gzip on;
        gzip_static on;
        more_set_headers Cache-Control public, max-age=2419200, immutable;
      '';
    };

    locations."/" = {
      proxyPass = "http://localhost:${toString cfg.port}";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "Upgrade";
      '';
    };
  };

  systemdService = {
    description = "${serviceName} systemd service";
    wantedBy = ["default.target"];
    after =
      ["network.target"]
      ++ (
        if cfg.useDb
        then ["postgresql.service"]
        else []
      );
    requires =
      ["network.target"]
      ++ (
        if cfg.useDb
        then ["postgresql.service"]
        else []
      );

    serviceConfig = {
      User = user;
      Group = user;
      WorkingDirectory = "${dataDir}";
      ExecStartPre =
        if cfg.useDb
        then ["${cfg.package}/bin/migrate"]
        else [];
      ExecStart = "${lib.getExe cfg.package} start";
      ExecStop = "${lib.getExe cfg.package} stop";
      ExecReload = "${lib.getExe cfg.package} restart";
      EnvironmentFile = cfg.environmentFile;
      Restart = "on-failure";
      RestartSec = "5";
    };

    environment =
      {
        PHX_HOST = cfg.host;
        PORT = toString cfg.port;
        MIX_ENV = "prod";
        PHX_SERVER = "true";
        RELEASE_TMP = "/tmp/${serviceName}";
        ERL_CRASH_DUMP = "${dataDir}/erl_crash.dump";
        TZDATA_DIR = "${dataDir}/tzdata";
        HOME = "${dataDir}";
      }
      // cfg.extraEnvironmentVars;
  };
in {
  options.services."${serviceName}" = {
    enable = lib.mkEnableOption "${serviceName}";
    package = lib.mkPackageOption pkgs "${serviceName}" {};
    useNginx = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable NGINX proxy with SSL.";
    };
    useDb = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable postgres backend.";
    };
    redirectWww = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Redirect `www.${opt.host}` to `${opt.host}`. Ignored if `${opt.useNginx} is false.";
    };
    sslEmail = lib.mkOption {
      type = lib.types.str;
      example = "someuser@example.com";
      description = "The email to use for the letsencrypt certificate.";
    };
    user = lib.mkOption {
      type = lib.types.str;
      default = serviceName;
      description = "The user (and group) to use for the ${serviceName} service.";
    };
    host = lib.mkOption {
      type = lib.types.str;
      description = "The domain name for the ${serviceName} service.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 4000;
      description = "The port to listen on, 4000 by default. If `${opt.useNginx}` is enabled then it will proxy to this.";
    };
    environmentFile = lib.mkOption {
      type = lib.types.path;
      description = "A file containing all secrets and env required by the service.";
    };
    extraEnvironmentVars = lib.mkOption {
      type = lib.types.attrs;
      description = "Extra environment variables to append to the systemd service environment config";
      example = {
        ALGA_DASHBOARD_RELEASE = "true";
        ALGA_FIRMWARE_PATH = "${dataDir}/firmware";
        # Additional safeguard, in case `RELEASE_DISTRIBUTION=none` ever
        # stops disabling the start of EPMD.
        ERL_EPMD_ADDRESS = "127.0.0.1";
      };
      default = {};
    };
    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/${serviceName}";
      example = "/var/lib/${serviceName}";
      description = ''
        The working directory for the ${serviceName} systemd service.
      '';
    };
    extraSetup = lib.mkOption {
      type = lib.types.str;
      description = "Any extra commands to add to the activation script. This is run immediately after `${opt.dataDir}` is created.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.package != null;
        message = "A package is required";
      }
      {
        assertion = cfg.environmentFile != "";
        message = "The environment file is required";
      }
    ];

    users = {
      groups.${user} = {};
      users.${user} = {
        isSystemUser = true;
        group = user;
        home = dataDir;
        createHome = false;
      };
    };

    security.acme = lib.mkIf cfg.useNginx {
      defaults.webroot = "/var/lib/acme/acme-challenge/";
      certs."${cfg.host}" = {
        email = cfg.sslEmail;
        group = config.services.nginx.group;
      };

      certs."www.${cfg.host}" = lib.mkIf cfg.redirectWww {
        email = cfg.sslEmail;
        group = config.services.nginx.group;
      };
    };

    services = {
      nginx = lib.mkIf cfg.useNginx {
        enable = true;
        virtualHosts."${cfg.host}" = nginxHost;
        virtualHosts."www.${cfg.host}" = lib.mkIf cfg.redirectWww {
          forceSSL = true;
          useACMEHost = "www.${cfg.host}";
          globalRedirect = cfg.host;
        };
      };

      postgresql = lib.mkIf cfg.useDb {
        enable = true;
        ensureDatabases = [user];
        ensureUsers = [
          {
            name = user;
            ensureDBOwnership = true;
          }
        ];
      };
    };

    systemd.services.${serviceName} = systemdService;

    system.activationScripts."${serviceName}_setup" = let
      wrapped = pkgs.writers.writeBash "wrapped_${serviceName}" ''
        #!/usr/bin/env bash
        set -e
        set -a
        source ${cfg.environmentFile}
        set +a
        ${lib.getExe cfg.package} $1
      '';
    in {
      text = ''
        mkdir -p ${dataDir}
        ${cfg.extraSetup}
        cp -r ${cfg.package}/lib/tzdata-*/priv/release_ets ${dataDir}/tzdata/
        ln -sf ${wrapped} ${dataDir}/wrapped-emdash
        chown -R ${user}:${user} ${dataDir}
        chmod -R 700 ${dataDir}/tzdata
      '';
      deps = [];
    };

    system.activationScripts."${serviceName}_nginx_setup" = lib.mkIf cfg.useNginx {
      text = ''
        mkdir -p ${dataDir}/static

        cp -r ${cfg.package}/nginx ${dataDir}/
        cp -r ${cfg.package}/lib/${serviceName}-*/priv/static ${dataDir}/

        chown -R ${user}:nginx ${dataDir}/nginx
        chown -R ${user}:nginx ${dataDir}/static

        chmod -R 550 ${dataDir}/nginx
      '';
      deps = [];
    };
  };
}
