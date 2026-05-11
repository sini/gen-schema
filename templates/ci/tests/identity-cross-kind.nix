{ lib, schemaLib, ... }:
let
  inherit (schemaLib._internal) identityModule;
  mkEval =
    kind: modules:
    lib.evalModules {
      modules = [ (identityModule kind) ] ++ modules;
    };

  # Host "foo" and user "foo" must produce different hashes
  hostFoo = mkEval "host" [
    { options.name = lib.mkOption { type = lib.types.str; }; }
    { config.name = "foo"; }
  ];
  userFoo = mkEval "user" [
    { options.name = lib.mkOption { type = lib.types.str; }; }
    { config.name = "foo"; }
  ];
in
{
  identity-cross.test-host-user-different-hash = {
    expr = hostFoo.config.id_hash == userFoo.config.id_hash;
    expected = false;
  };
}
