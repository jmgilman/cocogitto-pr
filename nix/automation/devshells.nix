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
    nixago = [
      cell.configs.conform
      cell.configs.lefthook
      cell.configs.prettier
      cell.configs.treefmt
    ];
    commands = [
      {
        package = inputs.cells.cocogitto-pr.packages.cocogitto;
        name = "cog";
      }
      {
        name = "fmt";
        command = "treefmt";
        help = "Formats the book's markdown files";
        category = "Development";
      }
    ];
  };
}
