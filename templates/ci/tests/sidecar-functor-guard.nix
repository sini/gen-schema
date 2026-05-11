# __functor is reserved — declaring it as a sidecar key should throw.
{ lib, schemaLib, ... }:
let
  eval = lib.evalModules {
    modules = [{
      options.schema = schemaLib.mkSchemaOption {
        sidecars.__functor = { default = {}; };
      };
      config.schema.host.options.name = lib.mkOption { type = lib.types.str; };
    }];
  };
  # Force the schema kind evaluation to trigger the guard
  result = builtins.tryEval (
    builtins.deepSeq eval.config.schema.host eval.config.schema.host
  );
in
{
  "sidecar-functor".test-reserved-key-throws = {
    expr = result.success;
    expected = false;
  };
}
