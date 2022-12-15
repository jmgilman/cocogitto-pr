{ inputs
, cell
}:
let
  inherit (inputs) nixpkgs std;
  l = nixpkgs.lib // builtins;
  stdl = std.lib;

  setupWork = stdl.ops.mkSetup "work" [ ] ''
    mkdir -p $out/etc
    cat >$out/etc/gitconfig <<EOF
    [user]
      name = "github-actions[bot]"
      email = "41898282+github-actions[bot]@users.noreply.github.com"
    [safe]
        directory = /work
    EOF
    mkdir $out/work
  '';
  setupUser = stdl.ops.mkUser {
    user = "user";
    group = "user";
    uid = "1000";
    gid = "1000";
    withHome = true;
    withRoot = true;
  };
in
{
  default = stdl.ops.mkStandardOCI
    {
      name = "docker.io/cocogitto-pr";
      tag = "latest";
      operable = cell.packages.main_operable;
      setup = [ setupWork setupUser ];
      uid = "1000";
      gid = "1000";
      debug = true;
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
  dev = stdl.ops.mkDevOCI {
    name = "docker.io/cocogitto-pr-dev";
    tag = "latest";
    vscode = true;
    setup = [ setupWork setupUser ];
    devshell = inputs.cells.automation.devshells.default;
    labels = {
      title = "cocogitto-pr-dev";
      version = "0.1.0";
      url = "https://github.com/jmgilman/cocogitto-pr";
      source = "https://github.com/jmgilman/cocogitto-pr";
      description = ''
        Dev container for cocogitto-pr
      '';
    };
  };
}
