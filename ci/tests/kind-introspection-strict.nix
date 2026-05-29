# Kind-level strict: strict = false propagates to each kind result.
{
  lib,
  genSchema,
  ...
}:
let
  inherit (genSchema) mkSchemaOption;

  eval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption { strict = false; };
        config.schema.host = {
          options.name = lib.mkOption { type = lib.types.str; };
        };
      }
    ];
  };

  host = eval.config.schema.host;
in
{
  flake.tests.kind-introspection-strict = {
    test-strict-false-on-kind = {
      expr = host.strict;
      expected = false;
    };
  };
}
