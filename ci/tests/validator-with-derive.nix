{
  lib,
  genSchema,
  genMerge,
  genAlgebra,
  ...
}:
let
  schema = genSchema.evalSchema { } [
    {
      config.schema.host = {
        options.addr = genMerge.mkOption { type = genMerge.types.str; };
        validators = [
          (genSchema.mkValidator {
            name = "has-addr";
            pred = { addr, ... }: addr != "";
            message = "addr must not be empty";
          })
        ];
      };
    }
  ];

  eval = genMerge.evalModuleTree { } [
    {
      options.hosts = genSchema.mkInstanceRegistry {
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
      } schema.host;
      config.hosts.igloo.addr = "10.0.1.1";
    }
  ];
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
