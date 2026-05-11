{ lib, schemaLib, ... }:
let
  inherit (schemaLib._internal) mkIdentityModule;
  mkEval =
    kind: modules:
    lib.evalModules {
      modules = [ (mkIdentityModule kind) ] ++ modules;
    };

  # Same entity -> same hash
  evalA = mkEval "host" [
    { options.name = lib.mkOption { type = lib.types.str; }; }
    { config.name = "igloo"; }
  ];
  evalB = mkEval "host" [
    { options.name = lib.mkOption { type = lib.types.str; }; }
    { config.name = "igloo"; }
  ];

  # Different entity -> different hash
  evalC = mkEval "host" [
    { options.name = lib.mkOption { type = lib.types.str; }; }
    { config.name = "castle"; }
  ];
in
{
  identity-hash.test-same-entity-same-hash = {
    expr = evalA.config.id_hash == evalB.config.id_hash;
    expected = true;
  };
  identity-hash.test-different-entity-different-hash = {
    expr = evalA.config.id_hash == evalC.config.id_hash;
    expected = false;
  };
  identity-hash.test-hash-is-string = {
    expr = builtins.isString evalA.config.id_hash;
    expected = true;
  };
  identity-hash.test-hash-length = {
    expr = builtins.stringLength evalA.config.id_hash;
    expected = 64; # sha256 hex length
  };
}
