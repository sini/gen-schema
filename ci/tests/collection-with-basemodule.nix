# baseModule options coexist correctly with collection extraction.
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
        options.schema = genSchema.mkSchemaOption {
          baseModule.options.description = genMerge.mkOption {
            type = genMerge.types.str;
            default = "";
          };
          collections.tags = {
            default = [ ];
          };
        };
        options.hosts = genSchema.mkInstanceRegistry eval.config.schema.host { };
        config.schema.host = {
          tags = [
            "web"
            "prod"
          ];
          options.addr = genMerge.mkOption { type = genMerge.types.str; };
        };
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
    expr = eval.config.schema.host.tags;
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
