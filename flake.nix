{
  description = "gen-schema: typed record registry with extension points for the pure-gen module system";

  # Class layering: gen-prelude → gen-types → gen-merge → gen-schema. The library (./lib) is
  # nixpkgs-lib-free (checked by ci/tests/purity.nix): it drives the registry engine on gen-merge's
  # byte-mode evalModuleTree + gen-types leaf checkers, NOT lib.evalModules / lib.types. nixpkgs is
  # pulled ONLY in ci/ (the nix-unit harness + any non-schema `lib.*` the test corpus still uses).
  inputs = {
    gen-prelude.url = "github:sini/gen-prelude";
    gen-types.url = "github:sini/gen-types";
    gen-merge.url = "github:sini/gen-merge";
    gen-algebra.url = "github:sini/gen-algebra";
  };

  outputs =
    {
      gen-prelude,
      gen-merge,
      gen-algebra,
      ...
    }:
    {
      lib = import ./lib {
        prelude = gen-prelude.lib;
        merge = gen-merge.lib;
        algebra = gen-algebra.lib;
      };
      flakeModules.default = ./flakeModule.nix;
    };
}
