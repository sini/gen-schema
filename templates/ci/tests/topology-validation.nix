{
  lib,
  schemaLib,
  ...
}:
let
  inherit (schemaLib) mkSchemaOption;

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
        builtins.deepSeq eval.config.schema._meta.topology eval.config.schema._meta.topology
      );
    in
    !result.success;
in
{
  topology-validation = {
    test-unknown-parent-throws = {
      expr = throwsOnUnknownParent;
      expected = true;
    };
  };
}
