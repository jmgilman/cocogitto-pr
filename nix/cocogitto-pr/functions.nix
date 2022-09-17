{ inputs
, cell
}:
let
  inherit (inputs) nixpkgs std;
  l = nixpkgs.lib // builtins;
  n2c = inputs.n2c.packages.nix2container;
in
rec {
  /*
     Creates an entrypoint for a container.

     Args:
      contents: The string contents of the entrypoint script (written in bash)
      env: An attribute set of environment variables to set in the entrypoint

    Returns:
      A derivation that will build the entrypoint script.
   */
  mkEntrypoint = { contents, env ? { } }:
    let
      header = ''
        #!${nixpkgs.pkgsStatic.bash.out}/bin/bash

        set -euo pipefail

        ${l.concatStringsSep "\n" (l.mapAttrsToList (n: v: "export ${n}=${''"$''}{${n}:-${toString v}}${''"''}") env)}
      '';
    in
    nixpkgs.writeShellScriptBin "entrypoint"
      ''
        ${header}
        ${contents}
      '';
  /*
    Creates a configuration intended to be consumed by nix2container.buildImage.

    Args:
      name: The name of the container
      package: The primary application package to run in the container. This
        package will be isolated to a separate layer for caching purposes.
      entrypoint: The entrypoint to use for the container. This should be a
        derivation created by mkEntrypoint.
      runtimeInputs: Additional list of runtime dependencies to include in the
        container.
      labels: An attribute set of image labels to apply to the container. The
      names are automatically prepended with "org.opencontainers.image".
      isCommand: Whether or not the entrypoint should be treated as a CMD.
        Defaults to false.

    Returns:
      An attribute set that can be passed to nix2container.buildImage.
  */
  mkImageConfig =
    { name
    , package
    , entrypoint
    , runtimeInputs ? [ ]
    , labels ? { }
    , isCommand ? false
    }:
    let
      entrypoint' = l.getExe entrypoint;
    in
    {
      inherit name;

      layers = [
        # Runtime input layer
        (n2c.buildLayer {
          copyToRoot = nixpkgs.buildEnv {
            name = "runtimeInputs";
            paths = runtimeInputs;
            pathsToLink = [ "/bin" ];
          };
          maxLayers = 10;
        })
        # Package layer
        (n2c.buildLayer {
          copyToRoot = nixpkgs.buildEnv {
            name = "package";
            paths = [ package ];
            pathsToLink = [ "/bin" ];
          };
          maxLayers = 90;
        })
      ];

      config = {
        User = "65534"; # nobody
        Group = "65534"; # nobody
        Labels = l.mapAttrs' (n: v: l.nameValuePair "org.opencontainers.image.${n}" v) labels;
      } // (if isCommand then
        { Cmd = [ entrypoint' ]; } else { Entrypoint = [ entrypoint' ]; });
    };
  # A convenience function for accessing nix2container.buildImage
  buildImage = config: n2c.buildImage (mkImageConfig config);
}
