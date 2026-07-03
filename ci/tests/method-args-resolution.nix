{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) mkSchemaOption schemaFn;

  eval = genMerge.evalModuleTree {
    modules = [
      {
        options.schema = mkSchemaOption { };
        config.schema.host = {
          options.name = genMerge.mkOption { type = genMerge.types.str; };
          options.role = genMerge.mkOption { type = genMerge.types.str; };
          methods.describe = schemaFn "Describe this host" genMerge.types.str (
            { name, role, ... }: "${name} is a ${role}"
          );
        };
      }
    ];
  };

  hostKind = eval.config.schema.host;

  instance = genMerge.evalModuleTree {
    modules = [
      hostKind
      {
        config.name = "igloo";
        config.role = "webserver";
      }
    ];
  };
in
{
  flake.tests.method-args.test-describe-resolves-name = {
    expr = instance.config.describe;
    expected = "igloo is a webserver";
  };
}
