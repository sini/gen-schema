{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) mkSchemaOption mkInstanceRegistry;

  eval = genMerge.evalModuleTree {
    modules = [
      {
        options.schema = mkSchemaOption { };
        options.hosts = mkInstanceRegistry eval.config.schema.host { };
        config.schema.host = {
          options.name = genMerge.mkOption { type = genMerge.types.str; };
          options.addr = genMerge.mkOption { type = genMerge.types.str; };
        };
        config.hosts.igloo.addr = "10.0.1.1";
      }
    ];
  };

  inherit (eval.config.hosts) igloo;
in
{
  flake.tests.instance-type = {
    test-name-from-key = {
      expr = igloo.name;
      expected = "igloo";
    };
    test-schema-option-works = {
      expr = igloo.addr;
      expected = "10.0.1.1";
    };
    test-has-id-hash = {
      expr = builtins.isString igloo.id_hash;
      expected = true;
    };
    test-id-hash-length = {
      expr = builtins.stringLength igloo.id_hash;
      expected = 64;
    };
  };
}
