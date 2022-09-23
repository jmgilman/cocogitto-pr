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
    Creates a new setup task for configuring a container.

    Args:
      name: A name for the task.
      perms: An attribute set of permissions to set for this task.
      contents: The contents of the setup task. This is a bash script.

    Returns:
      A setup task.
  */
  mkSetup = name: perms: contents:
    let
      setup = nixpkgs.runCommandNoCC "oci-setup-${name}" { } contents;
    in
    setup // l.optionalAttrs (perms != { })
      (
        l.recursiveUpdate { passthru.perms = perms; } { passthru.perms.path = setup; }
      );

  /*
    Creates a setup task which adds the given user to the container.

    Args:
      user: Username
      uid: User ID
      group: Group name
      gid: Group ID
      withHome: If true, creates a home directory for the user.

    Returns:
      A setup task which adds the user to the container.
  */
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
    # https://github.com/NixOS/nixpkgs/blob/master/pkgs/build-support/docker/default.nix#L177-L199
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

  /*
    Makes a package operable by configuring the necessary runtime environment.

    Args:
      package: The package to wrap.
      runtimeScript: A bash script to run at runtime.
      runtimeEnv: An attribute set of environment variables to set at runtime.
      runtimeInputs: A list of packages to add to the runtime environment.
      livenessProbe: An optional derivation to run to check if the program is alive.
      readinessProbe: An optional derivation to run to check if the program is ready.

    Returns:
      An operable for the given package.
  */
  mkOperable =
    { package
    , runtimeScript
    , runtimeEnv ? { }
    , runtimeInputs ? [ ]
    , debugInputs ? [ ]
    , livenessProbe ? null
    , readinessProbe ? null
    }:
    (writeScript
      {
        inherit runtimeInputs runtimeEnv;
        name = "operable-${package.name}";
        text = runtimeScript;
      }) // {
      # The livenessProbe and readinessProbe are picked up in later stages
      passthru = {
        inherit package runtimeInputs debugInputs;
      } // l.optionalAttrs (livenessProbe != null) {
        inherit livenessProbe;
      } // l.optionalAttrs (readinessProbe != null) {
        inherit readinessProbe;
      };
    };

  /*
    Creates an OCI container image using the given operable.

    Args:
      name: The name of the image.
      tag: Optional tag of the image (defaults to output hash)
      setup: A list of setup tasks to run to configure the container.
      uid: The user ID to run the container as.
      gid: The group ID to run the container as.
      perms: A list of permissions to set for the container.
      labels: An attribute set of labels to set for the container. The keys are
        automatically prefixed with "org.opencontainers.image".
      debug: Whether to include debug tools in the container (bash, coreutils).
      debugInputs: Additional packages to include in the container if debug is
        enabled.
      options: Additional options to pass to nix2container.

    Returns:
      An OCI container image (created with nix2container).
  */
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
    , options ? { }
    }:
    let
      # Links liveness and readiness probes (if present) to /bin/* for
      # convenience
      livenessLink = l.optionalString (operable.passthru.livenessProbe != null) "ln -s ${l.getExe operable.passthru.livenessProbe} $out/bin/live";
      readinessLink = l.optionalString (operable.passthru.readinessProbe != null) "ln -s ${l.getExe operable.passthru.readinessProbe} $out/bin/ready";

      # Configure debug shell
      debug-banner = nixpkgs.runCommandNoCC "debug-banner" { } ''
        ${nixpkgs.figlet}/bin/figlet -f banner "STD Debug" > $out
      '';
      debugShell = writeScript {
        name = "debug";
        runtimeInputs = [ nixpkgs.bashInteractive nixpkgs.coreutils ]
          ++ operable.passthru.debugInputs
          ++ operable.passthru.runtimeInputs;
        text = ''
          cat ${debug-banner}
          echo
          echo "=========================================================="
          echo "This debug shell contains the runtime environment and "
          echo "debug dependencies of the entrypoint."
          echo "To inspect the entrypoint run:"
          echo "cat /bin/entrypoint"
          echo "=========================================================="
          echo
          exec bash "$@"
        '';
      };
      debugShellLink = l.optionalString debug "ln -s ${l.getExe debugShell} $out/bin/debug";

      setupLinks = mkSetup "links" { } ''
        mkdir -p $out/bin
        ln -s ${l.getExe operable} $out/bin/entrypoint
        ${debugShellLink}
        ${livenessLink}
        ${readinessLink}
      '';

      # The root layer contains all of the setup tasks
      rootLayer = [ setupLinks ] ++ setup;

      # This is what get passed to nix2container.buildImage
      config = {
        inherit name;

        # Setup tasks can include permissions via the passthru.perms attribute
        perms = (l.map (s: l.optionalAttrs (s ? passthru && s.passthru ? perms) s.passthru.perms) setup) ++ perms;

        # Layers are nested to reduce duplicate paths in the image
        layers = [
          # Primary layer is the package layer
          (n2c.buildLayer {
            copyToRoot = [ operable.passthru.package ];
            maxLayers = 40;
            layers = [
              # Entrypoint layer
              (n2c.buildLayer {
                deps = [ operable ];
                maxLayers = 10;
              })
              # Runtime inputs layer
              (n2c.buildLayer {
                deps = operable.passthru.runtimeInputs;
                maxLayers = 10;
              })
            ]
            # Optional debug layer
            ++ l.optionals debug [
              (n2c.buildLayer {
                deps = [ debugShell ];
                maxLayers = 10;
              })
            ];
          })
          # Liveness and readiness probe layer
          (n2c.buildLayer {
            deps = [ ]
              ++ (l.optionals (operable.passthru ? livenessProbe) [ (n2c.buildLayer { deps = [ operable.passthru.livenessProbe ]; }) ])
              ++ (l.optionals (operable.passthru ? readinessProbe) [ (n2c.buildLayer { deps = [ operable.passthru.readinessProbe ]; }) ]);
            maxLayers = 10;
          })
        ];

        # Max layers is 127, we only go up to 120
        maxLayers = 40;
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

  writeScript =
    { name
    , text
    , runtimeInputs ? [ ]
    , runtimeEnv ? { }
    , runtimeShell ? nixpkgs.runtimeShell
    , checkPhase ? null
    }:
    nixpkgs.writeTextFile {
      inherit name;
      executable = true;
      destination = "/bin/${name}";
      text = ''
        #!${runtimeShell}
        set -o errexit
        set -o pipefail
        set -o nounset
        set -o functrace
        set -o errtrace
        set -o monitor
        set -o posix
        shopt -s dotglob

      '' + l.optionalString (runtimeInputs != [ ]) ''
        export PATH="${l.makeBinPath runtimeInputs}:$PATH"
      '' + l.optionalString (runtimeEnv != { }) ''
        ${l.concatStringsSep "\n" (l.mapAttrsToList (n: v: "export ${n}=${''"$''}{${n}:-${toString v}}${''"''}") runtimeEnv)}
      '' +
      ''

        ${text}
      '';

      checkPhase =
        if checkPhase == null then ''
          runHook preCheck
          ${nixpkgs.stdenv.shellDryRun} "$target"
          ${nixpkgs.shellcheck}/bin/shellcheck "$target"
          runHook postCheck
        ''
        else checkPhase;

      meta.mainProgram = name;
    };
}

