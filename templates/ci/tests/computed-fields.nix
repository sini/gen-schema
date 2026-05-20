{ lib, schemaLib, ... }:
let
  inherit (schemaLib) mkSchemaOption;

  eval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption {
          sidecars.tags = {
            default = [ ];
          };
          computed = _kind: sidecars: _defs: {
            tagCount = builtins.length sidecars.tags;
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
  computed.test-tag-count-populated = {
    expr = eval.config.schema.host.tagCount;
    expected = 3;
  };
  computed.test-tag-count-empty = {
    expr = eval.config.schema.app.tagCount;
    expected = 0;
  };
}
