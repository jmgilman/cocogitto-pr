{ inputs
, cell
}:
let
  inherit (inputs) nixpkgs std;
  l = nixpkgs.lib // builtins;

  setupWork = nixpkgs.runCommand "setup-work" { } ''
    mkdir -p $out/work
  '';
  setupUser = cell.functions.mkUserSetup {
    user = "user";
    group = "user";
    uid = "1000";
    gid = "1000";
  };
in
{
  default = cell.functions.mkOCI
    {
      name = "docker.io/cocogitto-pr";
      tag = "latest";
      operable = cell.packages.main_operable;
      setup = [ setupWork setupUser ];
      uid = "1000";
      gid = "1000";
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
