# __functor is reserved — declaring it as a collection key should throw.
{ lib, genSchema, ... }:
let
  eval = lib.evalModules {
    modules = [
      {
        options.schema = genSchema.mkSchemaOption {
          collections.__functor = {
            default = { };
          };
        };
        config.schema.host.options.name = lib.mkOption { type = lib.types.str; };
      }
    ];
  };
  # Force the schema kind evaluation to trigger the guard
  result = builtins.tryEval (builtins.deepSeq eval.config.schema.host eval.config.schema.host);
in
{
  flake.tests."collection-functor".test-reserved-key-throws = {
    expr = result.success;
    expected = false;
  };
}
