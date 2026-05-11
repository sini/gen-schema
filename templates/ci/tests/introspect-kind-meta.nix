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

  meta = eval.config.schema._meta.kindMeta "host";

  # Filter out internal options for assertions
  userOpts = builtins.filter (n: !(lib.hasPrefix "_" n) && n != "id_hash") meta.optionNames;
in
{
  introspect-meta.test-option-names-contain-name = {
    expr = builtins.elem "name" meta.optionNames;
    expected = true;
  };
  introspect-meta.test-option-names-contain-addr = {
    expr = builtins.elem "addr" meta.optionNames;
    expected = true;
  };
  introspect-meta.test-has-identity = {
    expr = meta.hasIdentity;
    expected = true;
  };
  introspect-meta.test-user-opts = {
    expr = lib.sort (a: b: a < b) userOpts;
    expected = [
      "addr"
      "name"
    ];
  };
}
