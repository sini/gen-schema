# Registry applyPipeline throws when validators fail (no custom onError).
# This tests the pipeline's default error path, not the standalone validateInstances API.
{ lib, schemaLib, ... }:
let
  eval = lib.evalModules {
    modules = [{
      options.schema = schemaLib.mkSchemaOption {};
      options.hosts = schemaLib.mkInstanceRegistry eval.config.schema "host" {};
      config.schema.host = {
        options.addr = lib.mkOption { type = lib.types.str; };
        validators = [
          (schemaLib.mkValidator "has-addr" ({ addr, ... }: addr != "") "addr required")
        ];
      };
      config.hosts.bad.addr = "";
    }];
  };
  result = builtins.tryEval (builtins.deepSeq eval.config.hosts eval.config.hosts);
in
{
  "validator-pipeline".test-default-throws = {
    expr = result.success;
    expected = false;
  };
}
