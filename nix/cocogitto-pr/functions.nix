{ inputs
, cell
}:
let
  inherit (inputs) nixpkgs std;
  l = nixpkgs.lib // builtins;
  n2c = inputs.n2c.packages.nix2container;
  stdl = std.std.lib;
in
{
  mkDevOCI =
    { name
    , devshell
    , runtimeShell ? nixpkgs.bashInteractive
    , tag ? ""
    , setup ? [ ]
    , perms ? [ ]
    , labels ? { }
    , options ? { }
    }:
    let
      # Valid shells for direnv hook
      shellName = l.baseNameOf (l.getExe runtimeShell);
      shellConfigs = {
        bash = ''
          mkdir -p $out/home/user
          cat >$out/home/user/.bashrc << EOF
          eval "\$(direnv hook bash)"
          EOF
        '';
        zsh = ''
          mkdir -p $out/home/user
          cat >$out/home/user/.zshrc << EOF
          eval "\$(direnv hook zsh)"
          EOF
        '';
      };

      # Configure local user
      setupUser = stdl.mkUser {
        user = "user";
        group = "user";
        uid = "1000";
        gid = "1000";
        withHome = true;
      };

      # Configure working directory
      setupWork = stdl.mkSetup "work" [ ] ''
        mkdir -p $out/work
      '';

      # Configure tmp directory
      setupTemp = stdl.mkSetup "tmp"
        [
          {
            regex = ".*";
            mode = "0777";
          }
        ]
        ''
          mkdir -p $out/tmp
        '';

      # Configure nix
      setupNix = stdl.mkSetup "nix" [ ] ''
        mkdir -p $out/etc
        echo "sandbox = false" > $out/etc/nix.conf
        echo "experimental-features = nix-command flakes" >> $out/etc/nix.conf
      '';

      # Configure direnv
      setupDirenv = stdl.mkSetup "direnv"
        [{
          regex = "/home/user";
          mode = "0744";
          uid = 1000;
          gid = 1000;
        }]
        (''
          mkdir -p $out/etc
          cat >$out/etc/direnv.toml << EOF
          [global]
          warn_timeout = "10m"
          [whitelist]
          prefix = [ "/" ]
          EOF
        '' + shellConfigs.bash);

      entrypoint = stdl.writeScript {
        name = "entrypoint";
        text = ''
          #!${l.getExe runtimeShell}

          ${l.getExe runtimeShell}
        '';
      };
    in
    stdl.mkOCI inputs {
      inherit entrypoint name tag labels perms;

      uid = "1000";
      gid = "1000";

      setup = [
        setupDirenv
        setupNix
        setupTemp
        setupUser
        setupWork
      ] ++ setup;

      layers = [
        (n2c.buildLayer {
          copyToRoot = [
            (nixpkgs.buildEnv
              {
                name = "devshell";
                paths = [
                  devshell
                  runtimeShell
                  nixpkgs.coreutils
                  nixpkgs.direnv
                  nixpkgs.git
                  nixpkgs.nix
                  nixpkgs.gnused
                ];
                pathsToLink = [ "/bin" ];
              })
          ] ++ [ nixpkgs.cacert ];
          maxLayers = 50;
        })
      ];

      options = (l.recursiveUpdate options {
        initializeNixDatabase = true;
        nixUid = 1000;
        nixGid = 1000;
        config = {
          Env = [
            "DIRENV_CONFIG=/etc"
            "HOME=/home/user"
            "NIX_CONF_DIR=/etc"
            "NIX_PAGER=cat"
            "NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
            "USER=user"
          ];
        };
      });
    };
}

