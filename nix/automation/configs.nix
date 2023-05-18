{ inputs
, cell
}:
let
  inherit (inputs) nixpkgs std;
  l = nixpkgs.lib // builtins;
in
{
  conform = std.lib.cfg.conform {
    data = {
      commit = {
        header = { length = 89; };
        conventional = {
          types = [
            "build"
            "chore"
            "ci"
            "docs"
            "feat"
            "fix"
            "perf"
            "refactor"
            "style"
            "test"
          ];
        };
      };
    };
  };
  lefthook = std.lib.cfg.lefthook {
    data = {
      commit-msg = {
        commands = {
          conform = {
            run = "${nixpkgs.conform}/bin/conform enforce --commit-msg-file {1}";
          };
        };
      };
      pre-commit = {
        commands = {
          treefmt = {
            run = "${nixpkgs.treefmt}/bin/treefmt {staged_files}";
          };
        };
      };
    };
  };
  prettier = std.lib.dev.mkNixago
    {
      data = {
        printWidth = 80;
        proseWrap = "always";
      };
      output = ".prettierrc";
      format = "json";
      packages = [ nixpkgs.nodePackages.prettier ];
    };
  treefmt = std.lib.cfg.treefmt
    {
      data = {
        formatter = {
          nix = {
            command = "nixpkgs-fmt";
            includes = [ "*.nix" ];
          };
          prettier = {
            command = "prettier";
            options = [ "--write" ];
            includes = [
              "*.md"
            ];
          };
        };
      };
      packages = [ nixpkgs.nixpkgs-fmt ];
    };
}
