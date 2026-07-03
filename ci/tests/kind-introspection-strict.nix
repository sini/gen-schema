# Kind-level strict: strict = false propagates to each kind result.
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
        options.schema = mkSchemaOption { strict = false; };
        config.schema.host = {
          options.name = genMerge.mkOption { type = genMerge.types.str; };
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
