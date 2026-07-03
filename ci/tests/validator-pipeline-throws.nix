# Registry applyPipeline throws when validators fail (no custom onError).
# This tests the pipeline's default error path, not the standalone validateInstances API.
{
  lib,
  genSchema,
  genMerge,
  genAlgebra,
  ...
}:
let
  eval = genMerge.evalModuleTree {
    modules = [
      {
        options.schema = genSchema.mkSchemaOption { };
        options.hosts = genSchema.mkInstanceRegistry eval.config.schema.host { };
        config.schema.host = {
          options.addr = genMerge.mkOption { type = genMerge.types.str; };
          validators = [
            (genSchema.mkValidator "has-addr" ({ addr, ... }: addr != "") "addr required")
          ];
        };
        config.hosts.bad.addr = "";
      }
    ];
  };
  result = builtins.tryEval (builtins.deepSeq eval.config.hosts eval.config.hosts);
in
{
  flake.tests."validator-pipeline".test-default-throws = {
    expr = result.success;
    expected = false;
  };
}
