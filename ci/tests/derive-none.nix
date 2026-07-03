{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  eval = genMerge.evalModuleTree {
    modules = [
      {
        options.schema = genSchema.mkSchemaOption { };
        options.hosts = genSchema.mkInstanceRegistry eval.config.schema.host { };
        config.schema.host = {
          options.addr = genMerge.mkOption { type = genMerge.types.str; };
        };
        config.hosts.igloo.addr = "10.0.1.1";
      }
    ];
  };
in
{
  flake.tests."derive-none" = {
    test-basic-access = {
      expr = eval.config.hosts.igloo.addr;
      expected = "10.0.1.1";
    };
    test-name = {
      expr = eval.config.hosts.igloo.name;
      expected = "igloo";
    };
  };
}
