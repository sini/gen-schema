# Instances get identity hashing — bare schema kinds don't.
{ lib, schemaLib, ... }:
let
  inherit (schemaLib) mkSchemaOption mkInstanceRegistry;

  eval = lib.evalModules {
    modules = [{
      options.schema = mkSchemaOption {};
      options.hosts = mkInstanceRegistry eval.config.schema "host" {};
      config.schema.host.options.addr = lib.mkOption { type = lib.types.str; };
      config.hosts.igloo.addr = "10.0.1.1";
    }];
  };
in
{
  "instance-identity".test-instance-has-id-hash = {
    expr = builtins.isString eval.config.hosts.igloo.id_hash;
    expected = true;
  };
  "instance-identity".test-instance-has-identity-keys = {
    expr = eval.config.hosts.igloo._identity.keys;
    expected = [];
  };
}
