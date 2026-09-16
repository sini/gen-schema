# Instances get identity hashing — bare schema kinds don't.
{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) evalSchema mkInstanceRegistry;

  schema = evalSchema {
    modules = [
      { config.schema.host.options.addr = genMerge.mkOption { type = genMerge.types.str; }; }
    ];
  };

  eval = genMerge.evalModuleTree {
    modules = [
      {
        options.hosts = mkInstanceRegistry schema.host { };
        config.hosts.igloo.addr = "10.0.1.1";
      }
    ];
  };
in
{
  flake.tests."instance-identity".test-instance-has-id-hash = {
    expr = builtins.isString eval.config.hosts.igloo.id_hash;
    expected = true;
  };
  flake.tests."instance-identity".test-instance-has-identity-keys = {
    expr = eval.config.hosts.igloo._identity.keys;
    expected = [ ];
  };
}
