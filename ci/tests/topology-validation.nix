{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) mkSchemaOption;

  # Declaring parent = "nonexistent" should throw
  throwsOnUnknownParent =
    let
      result = builtins.tryEval (
        let
          eval = genMerge.evalModuleTree {
            modules = [
              {
                options.schema = mkSchemaOption { };
                config.schema.host = {
                  options.addr = genMerge.mkOption { type = genMerge.types.str; };
                };
                config.schema.user = {
                  parent = "nonexistent";
                  options.shell = genMerge.mkOption { type = genMerge.types.str; };
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
