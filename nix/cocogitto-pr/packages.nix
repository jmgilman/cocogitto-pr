{ inputs
, cell
,
}:
let
  inherit (inputs) nixpkgs std;
  l = nixpkgs.lib // builtins;
  stdl = std.lib;
in
rec {
  gitTiny = nixpkgs.gitMinimal.override { perlSupport = false; };
  cocogitto =
    let
      inherit (nixpkgs) lib rustPlatform fetchFromGitHub installShellFiles stdenv Security makeWrapper libgit2;
    in
    rustPlatform.buildRustPackage rec {
      pname = "cocogitto";
      version = "5.2.0";

      src = fetchFromGitHub {
        owner = "cocogitto";
        repo = pname;
        rev = version;
        sha256 = "sha256-ZjDZMI84z8riRtidZVeCktwJUMkZU28E23MveJSD7xY=";
      };

      cargoSha256 = "sha256-oaWWAVTKxrshfvqE+HMQ1WeeEz8lOE7qc6RrgSjDtdU=";

      # Test depend on git configuration that would likly exist in a normal user enviroment
      # and might be failing to create the test repository it works in.
      doCheck = false;

      nativeBuildInputs = [ installShellFiles makeWrapper ];

      buildInputs = [ libgit2 ] ++ lib.optional stdenv.isDarwin Security;

      postInstall = ''
        installShellCompletion --cmd cog \
          --bash <($out/bin/cog generate-completions bash) \
          --fish <($out/bin/cog generate-completions fish) \
          --zsh  <($out/bin/cog generate-completions zsh)
      '';

      meta = with lib; {
        description = "A set of cli tools for the conventional commit and semver specifications";
        homepage = "https://github.com/oknozor/cocogitto";
        license = licenses.mit;
        maintainers = with maintainers; [ travisdavis-ops ];
      };
    };
  main = stdl.ops.writeScript {
    name = "main";
    text = (builtins.readFile ./scripts/main.sh);
    runtimeShell = nixpkgs.pkgsStatic.bash.out;
  };
  main_operable = stdl.ops.mkOperable {
    package = main;
    runtimeScript = ''
      ${l.getExe main} "''${1}" "''${2}"
    '';
    runtimeInputs = [
      cell.packages.cocogitto
      cell.packages.gitTiny
      nixpkgs.gh
      nixpkgs.gnugrep
    ];
    runtimeShell = nixpkgs.pkgsStatic.bash.out;
  };

}
