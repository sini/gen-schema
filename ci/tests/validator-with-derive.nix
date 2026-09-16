{
  lib,
  genSchema,
  genMerge,
  genAlgebra,
  ...
}:
let
  schema = genSchema.evalSchema {
    modules = [
      {
        config.schema.host = {
          options.addr = genMerge.mkOption { type = genMerge.types.str; };
          validators = [
            (genSchema.mkValidator "has-addr" ({ addr, ... }: addr != "") "addr must not be empty")
          ];
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
          derive = instances: lib.mapAttrs (name: _: { tag = "valid-${name}"; }) instances;
        };
        config.hosts.igloo.addr = "10.0.1.1";
      }
    ];
  };
in
{
  flake.tests."validator-derive" = {
    test-tag-applied = {
      expr = eval.config.hosts.igloo.tag;
      expected = "valid-igloo";
    };
    test-addr-preserved = {
      expr = eval.config.hosts.igloo.addr;
      expected = "10.0.1.1";
    };
  };
}
