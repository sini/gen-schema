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
        options.hosts = genSchema.mkInstanceRegistry schema.host {
          extraModules = [
            {
              options.hashPrefix = genMerge.mkOption {
                type = genMerge.types.str;
                readOnly = true;
                internal = true;
              };
            }
          ];
          derive =
            instances: lib.mapAttrs (_: inst: { hashPrefix = builtins.substring 0 8 inst.id_hash; }) instances;
        };
        config.hosts.igloo.addr = "10.0.1.1";
      }
    ];
  };
in
{
  flake.tests."derive-hash" = {
    test-hash-prefix-length = {
      expr = builtins.stringLength eval.config.hosts.igloo.hashPrefix;
      expected = 8;
    };
    test-hash-prefix-matches = {
      expr = eval.config.hosts.igloo.hashPrefix;
      expected = builtins.substring 0 8 eval.config.hosts.igloo.id_hash;
    };
  };
}
