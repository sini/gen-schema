{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) mkSchemaOption renderDocs;

  eval = genMerge.evalModuleTree {
    modules = [
      {
        options.schema = mkSchemaOption { };
        config.schema.host = {
          options.name = genMerge.mkOption {
            type = genMerge.types.str;
            description = "Hostname";
          };
          options.addr = genMerge.mkOption {
            type = genMerge.types.str;
            description = "IP address";
          };
        };
      }
    ];
  };

  rendered = renderDocs eval.config.schema;
in
{
  flake.tests.docs.test-contains-kind-heading = {
    expr = lib.hasInfix "## host" rendered;
    expected = true;
  };
  flake.tests.docs.test-contains-option-name = {
    expr = lib.hasInfix "name" rendered;
    expected = true;
  };
  flake.tests.docs.test-contains-table-header = {
    expr = lib.hasInfix "| Option | Type |" rendered;
    expected = true;
  };
  flake.tests.docs.test-is-string = {
    expr = builtins.isString rendered;
    expected = true;
  };
}
