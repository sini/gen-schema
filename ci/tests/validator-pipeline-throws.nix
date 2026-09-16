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
  schema = genSchema.evalSchema {
    modules = [
      {
        config.schema.host = {
          options.addr = genMerge.mkOption { type = genMerge.types.str; };
          validators = [
            (genSchema.mkValidator "has-addr" ({ addr, ... }: addr != "") "addr required")
          ];
        };
      }
    ];
  };

  eval = genMerge.evalModuleTree {
    modules = [
      {
        options.hosts = genSchema.mkInstanceRegistry schema.host { };
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
