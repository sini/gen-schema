{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) mkIdentityModule;
  mkEval =
    kind: modules:
    genMerge.evalModuleTree {
      modules = [ (mkIdentityModule kind) ] ++ modules;
    };

  evalA = mkEval "host" [
    { options.name = genMerge.mkOption { type = genMerge.types.str; }; }
    { config.name = "igloo"; }
  ];
  evalB = mkEval "host" [
    { options.name = genMerge.mkOption { type = genMerge.types.str; }; }
    { config.name = "igloo"; }
  ];
  evalC = mkEval "host" [
    { options.name = genMerge.mkOption { type = genMerge.types.str; }; }
    { config.name = "castle"; }
  ];

  # Identity reflection must also cover NIXPKGS-typed options (`lib.types.str`, whose type name is
  # "str", not gen-types' "string"): den declares every entity option with nixpkgs `lib.types`, so a
  # nixpkgs-str identity field (e.g. a home's `system`) must be reflected — else two instances that
  # differ only in it collapse to one id_hash (den's multi-system `home:ben` regression).
  evalNixStrA = mkEval "host" [
    { options.system = lib.mkOption { type = lib.types.str; }; }
    { config.system = "aarch64-linux"; }
  ];
  evalNixStrB = mkEval "host" [
    { options.system = lib.mkOption { type = lib.types.str; }; }
    { config.system = "x86_64-linux"; }
  ];
in
{
  flake.tests.identity-hash.test-same-entity-same-hash = {
    expr = evalA.config.id_hash == evalB.config.id_hash;
    expected = true;
  };
  flake.tests.identity-hash.test-different-entity-different-hash = {
    expr = evalA.config.id_hash == evalC.config.id_hash;
    expected = false;
  };
  flake.tests.identity-hash.test-hash-is-string = {
    expr = builtins.isString evalA.config.id_hash;
    expected = true;
  };
  flake.tests.identity-hash.test-hash-length = {
    expr = builtins.stringLength evalA.config.id_hash;
    expected = 64;
  };
  # nixpkgs-str identity field is reflected: instances differing only in it hash differently.
  flake.tests.identity-hash.test-nixpkgs-str-field-reflected = {
    expr = evalNixStrA.config.id_hash == evalNixStrB.config.id_hash;
    expected = false;
  };
}
