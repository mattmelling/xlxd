{
  inputs = {
    libftd2xx = {
      url = "https://ftdichip.com/wp-content/uploads/2022/07/libftd2xx-x86_64-1.4.27.tgz";
      flake = false;
    };
  };
  outputs = { self, nixpkgs, ... }@inputs: let
    packages = {
      libftd2xx = pkgs: pkgs.stdenv.mkDerivation rec {
        name = "libftd2xx";
        src = inputs.libftd2xx;
        version = "1.4.27";
        installPhase = ''
          mkdir -p $out/lib/pkgconfig
          mkdir -p $out/include

          cp ftd2xx.h $out/include/
          cp build/libftd2xx.so.* $out/lib
          cp -r build/libftd2xx $out/lib/
          cp build/libftd2xx.a $out/lib/

          cat <<EOF > $out/lib/pkgconfig/ftd2xx.pc
          prefix=$out
          exec_prefix=$out
          libdir=$out/lib
          includedir=/usr/include
          Name: ftd2xx
          Description: libftd2xx
          Version: ${version}
          Libs: -L$out/lib
          Cflags: -I$out/include
          EOF
      '';
      };
      ambed = pkgs: pkgs.stdenv.mkDerivation (let
        libftd2xx = packages.libftd2xx pkgs;
      in {
        name = "ambed";
        version = "0.1";
        src = ./.;
        makeFlags = [
          "-C ambed"
          "PREFIX=$(out)"
          "RPATH=${libftd2xx}/lib"
        ];
        buildInputs = with pkgs; [
          libftd2xx
          pkg-config
        ];
      });
      xlxd = pkgs: pkgs.stdenv.mkDerivation {
        name = "xlxd";
        version = "0.1";
        src = ./.;
        makeFlags = [
          "-C src"
          "PREFIX=$(out)"
        ];
        postPatch = ''
          substituteInPlace src/main.h \
              --replace "#define RUN_AS_DAEMON" "//#define RUN_AS_DAEMON" \
              --replace "/var/log/xlxd.xml" "/var/lib/xlxd/xlxd.xml" \
              --replace "/xlxd/xlxd.whitelist" "/etc/xlxd/xlxd.whitelist" \
              --replace "/xlxd/xlxd.blacklist" "/etc/xlxd/xlxd.blacklist" \
              --replace "/xlxd/xlxd.interlink" "/etc/xlxd/xlxd.interlink" \
              --replace "/xlxd/xlxd.terminal" "/etc/xlxd/xlxd.terminal" \
              --replace "/var/log/xlxd.debug" "/var/lib/xlxd/xlxd.debug" \
              --replace "#define YSF_AUTOLINK_ENABLE             0" "#define YSF_AUTOLINK_ENABLE 1"
        '';
      };
      xlxd-dashboard = pkgs: pkgs.stdenv.mkDerivation {
        name = "xlxd-dashboard";
        version = "0.1";
        src = ./dashboard;
        installPhase = ''
          mkdir -p $out
          cp -R ./* $out
        '';
        postPatch = ''
          substituteInPlace pgs/config.inc.php \
              --replace '../config.inc.php' '/etc/xlxd/config.inc.php'
        '';
      };
    };
  in {
    devShell.x86_64-linux = let
      pkgs = import nixpkgs {
        system = "x86_64-linux";
      };
    in pkgs.mkShell {
      buildInputs = with pkgs; [
        pkg-config
        self.packages.x86_64-linux.libftd2xx
      ];
    };
    packages.x86_64-linux = let
      pkgs = import nixpkgs {
        system = "x86_64-linux";
      };
    in builtins.mapAttrs (name: pkg: pkg pkgs) packages;
    overlays.default = final: pkgs: builtins.mapAttrs (name: pkg: pkg pkgs) packages;
    nixosModules = rec {
      all = [ xlxd ambed xlxd-dashboard ];
      xlxd = { pkgs, lib, config, ... }: let
        cfg = config.services.xlxd;
      in {
        options = {
          services.xlxd = with lib.types; {
            enable = lib.mkEnableOption "XLX Multi-mode Reflector";
            callsign = lib.mkOption {
              type = str;
            };
            bind = lib.mkOption {
              type = str;
              default = "0.0.0.0";
            };
            ambed = lib.mkOption {
              type = str;
              default = "127.0.0.1";
            };
            openFirewall = lib.mkOption {
              type = bool;
              default = false;
            };
          };
        };
        config = lib.mkIf cfg.enable {
          systemd.services.xlxd = {
            enable = true;
            wantedBy = [ "network-online.target"];
            script = ''
              #!${pkgs.stdenv.shell}
              ${pkgs.xlxd}/bin/xlxd ${cfg.callsign} ${cfg.bind} ${cfg.ambed}
            '';
            serviceConfig = {
              ExecStartPost = let
                script = pkgs.writeScriptBin "xlxd-exec-start-post" ''
                  #!${pkgs.stdenv.shell}
                  umask 022
                  ${pkgs.procps}/bin/pgrep xlxd > /var/lib/xlxd/xlxd.pid
                '';
              in "${script}/bin/xlxd-exec-start-post";
            };
          };
          networking.firewall = lib.mkIf cfg.openFirewall {
            allowedTCPPorts = [ 8080 ];
            allowedUDPPorts = [
              10001
              10002
              42000
              30001
              20001
              30051
              62030
              8880
              10100
              10101
              10199
              12345
              12346
              40000
              21110
            ];
          };
          environment.etc = {
            "xlxd/xlxd.blacklist".text = ''
              ##############################################################################
              #  XLXD blacklist file
              #
              #  one line per entry
              #  each entry is explicitely denied access (blacklisted)
              #  you can use * as last wildcard character
              #  example:
              #    *     -> deny access to  eveybody !!!
              #    LX*   -> deny access to all callsign starting with LX
              #    LX3JL -> deny access to LX3JL exactly
              #
              #############################################################################
            '';
            "xlxd/xlxd.whitelist".text = ''
              ##############################################################################
              #  XLXD whitelist file
              #
              #  one line per entry
              #  each entry is explicitely authorised (whitelisted)
              #  you can use * as last wildcard character
              #  example:
              #    *     -> authorize eveybody
              #    LX*   -> authorize all callsign starting with LX
              #    LX3JL -> authorize LX3JL exactly
              #
              #############################################################################
              *
            '';
            "xlxd/xlxd.interlink".text = ''
              ##############################################################################
              #  XLXD interlink file
              #
              #  one line per entry
              #  each entry specify a remote XLX to peer with
              #  format:
              #    <callsign> <ip> <list of module shared>
              #  example:
              #    XLX270 158.64.26.132 ACD
              #
              #  note: the remote XLX must list this XLX in it's interlink file
              #        for the link to be established
              #
              #############################################################################
            '';
            "xlxd/xlxd.terminal".text = ''
              #########################################################################################
              #  XLXD terminal option file
              #
              #  one line per entry
              #  each entry specifies a terminal option
              #
              #  Valid option:
              #  address <ip>      - Ip address to be used by the terminal route responder
              #                      By default, the request destination address is used.
              #                      If the system is behind a router, set it to the public IP
              #                      If the system runs on the public IP, leave unset.
              #  modules <modules> - a string with all modules to accept a terminal connection
              #                      Default value is "*", meaning accept all
              #
              #########################################################################################
              #address 193.1.2.3
              #modules BCD
            '';
          };
        };
      };
      ambed = { pkgs, lib, config, ... }: let
        cfg = config.services.ambed;
      in {
        options = {
          services.ambed = with lib.types; {
            enable = lib.mkEnableOption "AMBEd transcoder";
            bind = lib.mkOption {
              type = str;
              default = "0.0.0.0";
            };
          };
        };
        config = lib.mkIf cfg.enable {
          systemd.services.ambed = {
            enable = true;
            wantedBy = [ "network-online.target"];
            script = ''
              #!${pkgs.stdenv.shell}
              ${pkgs.ambed}/bin/ambed ${cfg.bind}
            '';
          };
        };
      };
      xlxd-dashboard = { pkgs, lib, config, ... }: let
        cfg = config.services.xlxd-dashboard;
      in {
        options = with lib.types; {
          services.xlxd-dashboard = {
            enable = lib.mkEnableOption "XLX Dashboard";
            virtualHost = lib.mkOption {
              type = str;
              default = config.networking.hostName;
            };
            user = lib.mkOption {
              type = str;
              default = "xlxd";
            };
            poolConfig = lib.mkOption {
              type = attrsOf (oneOf [ str int bool ]);
              default = {
                "pm" = "dynamic";
                "pm.max_children" = 32;
                "pm.start_servers" = 2;
                "pm.min_spare_servers" = 2;
                "pm.max_spare_servers" = 4;
                "pm.max_requests" = 500;
              };
            };
            openFirewall = lib.mkOption {
              type = bool;
              default = false;
            };
            settings = {
              contactEmail = lib.mkOption {
                type = str;
              };
              ircddb = {
                show = lib.mkOption {
                  type = bool;
                  default = false;
                };
              };
              callingHome = {
                active = lib.mkOption {
                  type = bool;
                  default = false;
                };
                dashboardUrl = lib.mkOption {
                  type = str;
                };
                country = lib.mkOption {
                  type = str;
                };
                comment = lib.mkOption {
                  type = str;
                };
              };
              extraConfig = lib.mkOption {
                type = str;
                default = "";
              };
            };
          };
        };
        config = lib.mkIf cfg.enable {
          services = {
            phpfpm.pools.xlxd-dashboard = {
              inherit (cfg) user;
              group = config.services.nginx.group;
              settings =  {
                "listen.owner" = config.services.nginx.user;
                "listen.group" = config.services.nginx.group;
              } // cfg.poolConfig;
            };
            nginx = {
              enable = true;
              virtualHosts."${cfg.virtualHost}" = {
                root = "${pkgs.xlxd-dashboard}";
                locations."/".tryFiles = "$uri /index.php$is_args$args";
                locations."~ \.php(/|$)".extraConfig = ''
                  include ${config.services.nginx.package}/conf/fastcgi_params;
                  include ${pkgs.nginx}/conf/fastcgi.conf;
                  fastcgi_split_path_info ^(.+\.php)(.+)$;
                  fastcgi_pass unix:${config.services.phpfpm.pools.xlxd-dashboard.socket};
                  fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
              '';
              };
            };
          };
          environment.etc."xlxd/config.inc.php".text = ''
            <?php
            $PageOptions["ContactEmail"] = "${cfg.settings.contactEmail}";
            $PageOptions["IRCDDB"]["Show"] = ${if cfg.settings.ircddb.show then "true" else "false"};
            $Service["XMLFile"] = "/var/lib/xlxd/xlxd.xml";
            $CallingHome["Active"] = ${if cfg.settings.callingHome.active then "true" else "false"};
            $CallingHome["MyDashBoardURL"] = "${cfg.settings.callingHome.dashboardUrl}";
            $CallingHome["Country"] = "${cfg.settings.callingHome.country}";
            $CallingHome["Comment"] = "${cfg.settings.callingHome.comment}";

            $CallingHome["HashFile"] = "/var/lib/xlxd/callinghome.php";
            $CallingHome["LastCallHomefile"] = "/var/lib/xlxd/lastcallhome.php";
            $Service['PIDFile'] = "/var/lib/xlxd/xlxd.pid";

            ${cfg.settings.extraConfig}
          '';
          systemd.tmpfiles.rules = let
            group = config.services.nginx.group;
          in [
            "d /var/lib/xlxd                 0750 ${cfg.user} ${group} - -"
          ];
          networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [
            80
          ];
          users.users."${cfg.user}" = {
            isSystemUser = true;
            group = config.services.nginx.group;
          };
        };
      };
    };
  };
}
