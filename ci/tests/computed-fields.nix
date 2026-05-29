{ lib, genSchema, ... }:
let
  inherit (genSchema) mkSchemaOption;

  eval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption {
          collections.tags = {
            default = [ ];
          };
          computed = collections: _defs: {
            tagCount = builtins.length collections.tags;
          };
        };
        config.schema.host = {
          options.name = lib.mkOption { type = lib.types.str; };
          tags = [
            "server"
            "linux"
            "production"
          ];
        };
        config.schema.app = {
          options.name = lib.mkOption { type = lib.types.str; };
        };
      }
    ];
  };
in
{
  flake.tests.computed.test-tag-count-populated = {
    expr = eval.config.schema.host.tagCount;
    expected = 3;
  };
  flake.tests.computed.test-tag-count-empty = {
    expr = eval.config.schema.app.tagCount;
    expected = 0;
  };
}
