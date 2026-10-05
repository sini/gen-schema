{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) mkSchemaOption schemaFn;

  eval = genMerge.evalModuleTree { } [
    {
      options.schema = mkSchemaOption { };
      config.schema.host = {
        options.name = genMerge.mkOption { type = genMerge.types.str; };
        options.role = genMerge.mkOption { type = genMerge.types.str; };
        methods.describe = schemaFn {
          description = "Describe this host";
          type = genMerge.types.str;
          fn = { name, role, ... }: "${name} is a ${role}";
        };
      };
    }
  ];

  hostKind = eval.config.schema.host;

  instance = genMerge.evalModuleTree { } [
    hostKind
    {
      config.name = "igloo";
      config.role = "webserver";
    }
  ];
in
{
  flake.tests.method-args.test-describe-resolves-name = {
    expr = instance.config.describe;
    expected = "igloo is a webserver";
  };
}
