{ inputs
, cell
}:
let
  inherit (inputs) nixpkgs std;
  l = nixpkgs.lib // builtins;
  # entrypoint = std.std.lib.writeShellEntrypoint inputs {
  #   package = cell.packages.main;
  #   runtimeInputs = [
  #     cell.packages.cocogitto
  #     cell.packages.gitTiny
  #     nixpkgs.gh
  #   ];
  #   entrypoint = ''
  #     ${l.getExe cell.packages.main} "''${1}" "''${2}"
  #   '';
  # };

  setupWork = nixpkgs.runCommand "setup-work" { } ''
    mkdir -p $out/work
  '';
in
{
  # default = entrypoint.mkOCI {
  #   name = "docker.io/cocogitto-pr";
  #   options = {
  #     tag = "latest";
  #     config.Labels = {
  #       "org.opencontainers.image.title" = "cocogitto-pr";
  #       "org.opencontainers.image.version" = "0.1.0";
  #       "org.opencontainers.image.url" = "https://github.com/jmgilman/cocogitto-pr";
  #       "org.opencontainers.image.source" = "https://github.com/jmgilman/cocogitto-pr";
  #       "org.opencontainers.image.description" = ''
  #         Github Action for generating preview PRs with cocogitto
  #       '';
  #     };
  #   };
  # };
  default = cell.functions.mkOCI
    {
      name = "docker.io/cocogitto-pr";
      tag = "latest";
      operable = cell.packages.main_operable;
      setup = [ setupWork ];
      debug = true;
      perms = [
        {
          path = setupWork;
          regex = ".*";
          mode = "0777";
        }
      ];
      options = {
        config.Volumes."/work" = { };
        config.WorkingDir = "/work";
      };
      labels = {
        title = "cocogitto-pr";
        version = "0.1.0";
        url = "https://github.com/jmgilman/cocogitto-pr";
        source = "https://github.com/jmgilman/cocogitto-pr";
        description = ''
          Github Action for generating preview PRs with cocogitto
        '';
      };
    };
}
