{ inputs
, cell
}:
let
  inherit (inputs) nixpkgs std;
  l = nixpkgs.lib // builtins;
  n2c = inputs.n2c.packages.nix2container;
in
rec {
  mkUser = { user, uid, group, gid, withHome ? false }:
    let
      perms = l.optionalAttrs withHome {
        regex = "/home/${user}";
        mode = "0744";
        uid = l.toInt uid;
        gid = l.toInt gid;
        uname = user;
        gname = group;
      };
    in
    mkSetup "users" perms (''
      mkdir -p $out/etc/pam.d

      echo "${user}:x:${uid}:${gid}::" > $out/etc/passwd
      echo "${user}:!x:::::::" > $out/etc/shadow

      echo "${group}:x:${gid}:" > $out/etc/group
      echo "${group}:x::" > $out/etc/gshadow

      cat > $out/etc/pam.d/other <<EOF
      account sufficient pam_unix.so
      auth sufficient pam_rootok.so
      password requisite pam_unix.so nullok sha512
      session required pam_unix.so
      EOF

      touch $out/etc/login.defs
    '' + l.optionalString withHome "\nmkdir -p $out/home/${user}");

  mkSetup = name: perms: script:
    let
      setup = nixpkgs.runCommand "oci-setup-${name}" { } script;
    in
    setup // l.optionalAttrs (perms != { })
      (
        l.recursiveUpdate { passthru.perms = perms; } { passthru.perms.path = setup; }
      );

  mkOperable =
    { package
    , runtimeScript
    , runtimeEnv ? { }
    , runtimeInputs ? [ ]
    , livenessProbe ? null
    , readinessProbe ? null
    }:
    let
      text = ''
        ${l.concatStringsSep "\n" (l.mapAttrsToList (n: v: "export ${n}=${''"$''}{${n}:-${toString v}}${''"''}") runtimeEnv)}
        ${runtimeScript}
      '';
    in
    (nixpkgs.writeShellApplication
      {
        inherit text runtimeInputs;
        name = "operable-${package.name}";
      }) // {
      passthru = {
        inherit package runtimeInputs;
      } // l.optionalAttrs (livenessProbe != null) {
        inherit livenessProbe;
      } // l.optionalAttrs (readinessProbe != null) {
        inherit readinessProbe;
      };
    };

  mkOCI =
    { name
    , operable
    , tag ? ""
    , setup ? [ ]
    , uid ? "65534"
    , gid ? "65534"
    , perms ? [ ]
    , labels ? { }
    , debug ? false
    , debugInputs ? [ ]
    , options ? { }
    }:
    let
      livenessLink = l.optionalString (operable.passthru.livenessProbe != null) "ln -s ${l.getExe operable.passthru.livenessProbe} $out/bin/live";
      readinessLink = l.optionalString (operable.passthru.readinessProbe != null) "ln -s ${l.getExe operable.passthru.readinessProbe} $out/bin/ready";

      mkLinks = nixpkgs.runCommand "mkLinks" { } ''
        mkdir -p $out/bin
        ln -s ${l.getExe operable} $out/bin/entrypoint
        ${livenessLink}
        ${readinessLink}
      '';

      rootLayer = [ mkLinks ]
        ++ setup
        ++ l.optionals debug [
        (nixpkgs.buildEnv {
          name = "root";
          paths = [ nixpkgs.bashInteractive nixpkgs.coreutils ] ++ debugInputs;
          pathsToLink = [ "/bin" ];
        })
      ];
      config = {
        inherit name;

        perms = (l.map (s: l.optionalAttrs (s ? passthru && s.passthru ? perms) s.passthru.perms) setup) ++ perms;

        layers = [
          (n2c.buildLayer {
            copyToRoot = [ operable.passthru.package ];
            maxLayers = 10;
            layers = [
              (n2c.buildLayer {
                deps = [ operable ];
                maxLayers = 10;
              })
              (n2c.buildLayer {
                deps = operable.passthru.runtimeInputs;
                maxLayers = 10;
              })
            ];
          })
          (n2c.buildLayer {
            deps = [ ]
              ++ (l.optionals (operable.passthru ? livenessProbe) [ (n2c.buildLayer { deps = [ operable.passthru.livenessProbe ]; }) ])
              ++ (l.optionals (operable.passthru ? readinessProbe) [ (n2c.buildLayer { deps = [ operable.passthru.readinessProbe ]; }) ]);
            maxLayers = 10;
          })
        ];

        maxLayers = 50;
        copyToRoot = rootLayer;

        config = {
          User = uid;
          Group = gid;
          Entrypoint = [ "/bin/entrypoint" ];
          Labels = l.mapAttrs' (n: v: l.nameValuePair "org.opencontainers.image.${n}" v) labels;
        };
      } // l.optionalAttrs (tag != "") { inherit tag; };
    in
    n2c.buildImage (l.recursiveUpdate config options);
}
