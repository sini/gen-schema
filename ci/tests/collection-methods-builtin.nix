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
        options.schema = mkSchemaOption {
          collections.tags = {
            default = [ ];
          };
        };
        config.schema.host = {
          options.name = genMerge.mkOption { type = genMerge.types.str; };
          tags = [ "server" ];
          methods.label = schemaFn "Label" genMerge.types.str ({ name, ... }: "host:${name}");
        };
      }
    ];
  };

  hostKind = eval.config.schema.host;

  instance = genMerge.evalModuleTree {
    modules = [
      hostKind
      { config.name = "igloo"; }
    ];
  };
in
{
  flake.tests.collection-methods.test-method-works = {
    expr = instance.config.label;
    expected = "host:igloo";
  };
  flake.tests.collection-methods.test-collection-on-kind = {
    expr = hostKind.tags;
    expected = [ "server" ];
  };
}
