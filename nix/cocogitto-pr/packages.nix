{ inputs
, cell
,
}: {
  gitTiny = inputs.nixpkgs.gitMinimal.override { perlSupport = false; };
  cocogitto = let
    inherit (inputs.nixpkgs) lib rustPlatform fetchFromGitHub installShellFiles stdenv Security makeWrapper libgit2;
  in rustPlatform.buildRustPackage rec {
    pname = "cocogitto";
    version = "5.1.0";

    src = fetchFromGitHub {
      owner = "oknozor";
      repo = pname;
      rev = version;
      sha256 = "sha256-q2WJKAXpIO+VsOFrjdyEx06yis8f2SkCuB0blUgqq0M=";
    };

    cargoSha256 = "sha256-UArYBcUkXPYlNRLQBMwNhsd3bNgLeEwtJdzepMTt2no=";

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
}
