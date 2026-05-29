{
  lib,
  genSchema,
  ...
}:
let
  inherit (genSchema) mkSchemaOption;

  # Declaring parent = "nonexistent" should throw
  throwsOnUnknownParent =
    let
      result = builtins.tryEval (
        let
          eval = lib.evalModules {
            modules = [
              {
                options.schema = mkSchemaOption { };
                config.schema.host = {
                  options.addr = lib.mkOption { type = lib.types.str; };
                };
                config.schema.user = {
                  parent = "nonexistent";
                  options.shell = lib.mkOption { type = lib.types.str; };
                };
              }
            ];
          };
        in
        builtins.deepSeq eval.config.schema._topology eval.config.schema._topology
      );
    in
    !result.success;
in
{
  flake.tests.topology-validation = {
    test-unknown-parent-throws = {
      expr = throwsOnUnknownParent;
      expected = true;
    };
  };
}
