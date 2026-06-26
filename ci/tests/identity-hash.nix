{ lib, genSchema, ... }:
let
  inherit (genSchema) mkIdentityModule;
  mkEval =
    kind: modules:
    lib.evalModules {
      modules = [ (mkIdentityModule kind) ] ++ modules;
    };

  evalA = mkEval "host" [
    { options.name = lib.mkOption { type = lib.types.str; }; }
    { config.name = "igloo"; }
  ];
  evalB = mkEval "host" [
    { options.name = lib.mkOption { type = lib.types.str; }; }
    { config.name = "igloo"; }
  ];
  evalC = mkEval "host" [
    { options.name = lib.mkOption { type = lib.types.str; }; }
    { config.name = "castle"; }
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
}
