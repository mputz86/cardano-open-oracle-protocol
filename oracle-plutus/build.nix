{ pkgs, haskell-nix, compiler-nix-name, plutarch, shellHook }:
haskell-nix.cabalProject' (plutarch.applyPlutarchDep pkgs {
  src = ./.;
  name = "oracle-plutus";
  inherit compiler-nix-name;
  #index-state = "2022-01-21T23:44:46Z";
  extraSources = [
    {
      src = plutarch;
      subdirs = [ "." "plutarch-extra" "plutarch-test" ];
    }
  ];
  modules = [
    (_: {
      packages = {
        # Enable strict builds
        oracle-plutus.configureFlags = [ "-f-dev" ];
      };
    }
    )
  ];
  shell = {
    withHoogle = true;

    exactDeps = true;
    nativeBuildInputs = with pkgs; [
      # Code quality
      ## Haskell/Cabal
      haskellPackages.apply-refact
      haskellPackages.fourmolu
      haskellPackages.cabal-fmt
      hlint
      ## Nix
      nixpkgs-fmt
    ];

    additional = ps: [
      ps.plutarch
      ps.plutus-ledger-api
    ];

    tools = {
      cabal = { };
    };
    shellHook = ''
      export LC_CTYPE=C.UTF-8
      export LC_ALL=C.UTF-8
      export LANG=C.UTF-8
      cd oracle-plutus
      ${shellHook}
    '';

  };
})