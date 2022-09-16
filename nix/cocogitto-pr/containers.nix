{ inputs
, cell
}:
let
  inherit (inputs) nixpkgs std;
  l = nixpkgs.lib // builtins;
  entrypoint = std.std.lib.writeShellEntrypoint inputs {
    package = cell.packages.cocogitto;
    entrypoint = ''
      cog --help
    '';
  };
in
{
  default = entrypoint.mkOCI "docker.io/cocogitto-pr";
}
