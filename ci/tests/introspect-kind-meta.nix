{ lib, schemaLib, ... }:
let
  inherit (schemaLib) mkSchemaOption;

  eval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption { };
        config.schema.host = {
          options.name = lib.mkOption { type = lib.types.str; };
          options.addr = lib.mkOption { type = lib.types.str; };
        };
      }
    ];
  };

  hostKind = eval.config.schema.host;
  optionNames = builtins.attrNames hostKind.options;

  # Filter out internal options for assertions
  userOpts = lib.filter (n: !(lib.hasPrefix "_" n) && n != "id_hash") optionNames;
in
{
  flake.tests.introspect-meta.test-option-names-contain-name = {
    expr = hostKind.options ? name;
    expected = true;
  };
  flake.tests.introspect-meta.test-option-names-contain-addr = {
    expr = hostKind.options ? addr;
    expected = true;
  };
  flake.tests.introspect-meta.test-user-opts = {
    expr = lib.sort (a: b: a < b) userOpts;
    expected = [
      "addr"
      "name"
    ];
  };
}
