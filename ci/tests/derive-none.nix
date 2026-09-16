{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  schema = genSchema.evalSchema {
    modules = [
      {
        config.schema.host = {
          options.addr = genMerge.mkOption { type = genMerge.types.str; };
        };
      }
    ];
  };

  eval = genMerge.evalModuleTree {
    modules = [
      {
        options.hosts = genSchema.mkInstanceRegistry schema.host { };
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
