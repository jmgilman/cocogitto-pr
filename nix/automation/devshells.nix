{ inputs
, cell
}:
let
  inherit (inputs) nixpkgs std;
  l = nixpkgs.lib // builtins;
in
l.mapAttrs (_: std.lib.dev.mkShell) {
  default = { ... }: {
    name = "cocogitto-pr devshell";
    imports = [ std.std.devshellProfiles.default ];
    nixago = [
      cell.configs.conform
      cell.configs.lefthook
      cell.configs.prettier
      cell.configs.treefmt
    ];
    packages = [
      nixpkgs.cocogitto
    ];
    commands = [
      {
        name = "fmt";
        command = "treefmt";
        help = "Formats the book's markdown files";
        category = "Development";
      }
    ];
  };
}
