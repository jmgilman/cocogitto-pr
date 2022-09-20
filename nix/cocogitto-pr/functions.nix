{ inputs
, cell
}:
let
  inherit (inputs) nixpkgs std;
  l = nixpkgs.lib // builtins;
  n2c = inputs.n2c.packages.nix2container;
in
rec {
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
    , perms ? { }
    , labels ? { }
    , debug ? false
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
          paths = [ nixpkgs.bashInteractive nixpkgs.coreutils ];
          pathsToLink = [ "/bin" ];
        })
      ];

      config = {
        inherit name perms tag;

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
          User = "65534"; # nobody
          Group = "65534"; # nobody
          Entrypoint = [ "/bin/entrypoint" ];
          Labels = l.mapAttrs' (n: v: l.nameValuePair "org.opencontainers.image.${n}" v) labels;
        };
      };
    in
    n2c.buildImage (l.recursiveUpdate config options);
}
