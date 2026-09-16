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
              options.tag = genMerge.mkOption {
                type = genMerge.types.str;
                readOnly = true;
                internal = true;
              };
            }
          ];
          derive = instances: lib.mapAttrs (name: _: { tag = "derived-${name}"; }) instances;
        };
        config.hosts.igloo.addr = "10.0.1.1";
        config.hosts.iceberg.addr = "10.0.1.2";
      }
    ];
  };
in
{
  flake.tests."derive-plain" = {
    test-igloo-tag = {
      expr = eval.config.hosts.igloo.tag;
      expected = "derived-igloo";
    };
    test-iceberg-tag = {
      expr = eval.config.hosts.iceberg.tag;
      expected = "derived-iceberg";
    };
    test-addr-preserved = {
      expr = eval.config.hosts.igloo.addr;
      expected = "10.0.1.1";
    };
  };
}
