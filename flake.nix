{
  inputs.n2c.url = "github:jmgilman/nix2container/change-owner";
  inputs.std.url = "github:jmgilman/std/oci";
  inputs.nixpkgs.url = "nixpkgs";
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
          (std.blockTypes.functions "functions")
        ];
      }
      {
        devShells = std.harvest inputs.self [ "automation" "devshells" ];
      };
}
