{
  inputs.n2c.url = "github:nlewo/nix2container";
  inputs.std.url = "github:divnix/std";
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
        ];
      }
      {
        devShells = std.harvest inputs.self [ "example" "devshells" ];
      };
}
