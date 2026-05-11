{ lib, schemaLib, ... }:
let
  inherit (schemaLib) mkSchemaOption renderDocs;

  eval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption { };
        config.schema.host = {
          options.name = lib.mkOption {
            type = lib.types.str;
            description = "Hostname";
          };
          options.addr = lib.mkOption {
            type = lib.types.str;
            description = "IP address";
          };
        };
      }
    ];
  };

  rendered = renderDocs eval.config.schema;
in
{
  docs.test-contains-kind-heading = {
    expr = lib.hasInfix "## host" rendered;
    expected = true;
  };
  docs.test-contains-option-name = {
    expr = lib.hasInfix "name" rendered;
    expected = true;
  };
  docs.test-contains-table-header = {
    expr = lib.hasInfix "| Option | Type |" rendered;
    expected = true;
  };
  docs.test-is-string = {
    expr = builtins.isString rendered;
    expected = true;
  };
}
