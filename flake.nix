{
  inputs.std.url = "github:divnix/std/v0.21.4";
  inputs.nixpkgs.url = "nixpkgs";
  inputs.cocogitto = {
    url = "github:cocogitto/cocogitto?ref=5.3.1";
    flake = false;
  };

  outputs = { std, ... } @ inputs:
    std.growOn
      {
        inherit inputs;
        cellsFrom = ./nix;
        cellBlocks = [
          (std.blockTypes.devshells "devshells")
          (std.blockTypes.nixago "configs")
          (std.blockTypes.containers "containers")
          (std.blockTypes.installables "packages")
        ];
      }
      {
        devShells = std.harvest inputs.self [ "automation" "devshells" ];
      };
}
