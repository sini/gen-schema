{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) mkSchemaOption;

  eval = genMerge.evalModuleTree {
    modules = [
      {
        options.schema = mkSchemaOption { };
        config.schema.host = {
          options.name = genMerge.mkOption { type = genMerge.types.str; };
          options.addr = genMerge.mkOption { type = genMerge.types.str; };
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
