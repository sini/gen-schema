# baseModule options coexist correctly with collection extraction.
{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  schema = genSchema.evalSchema {
    schemaOption = genSchema.mkSchemaOption {
      baseModule.options.description = genMerge.mkOption {
        type = genMerge.types.str;
        default = "";
      };
      collections.tags = {
        default = [ ];
      };
    };
    modules = [
      {
        config.schema.host = {
          tags = [
            "web"
            "prod"
          ];
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
  flake.tests."collection-base".test-base-option-on-instance = {
    expr = eval.config.hosts.igloo.description;
    expected = "";
  };
  flake.tests."collection-base".test-collection-on-kind = {
    expr = schema.host.tags;
    expected = [
      "web"
      "prod"
    ];
  };
  flake.tests."collection-base".test-both-coexist = {
    expr = eval.config.hosts.igloo.addr;
    expected = "10.0.1.1";
  };
}
