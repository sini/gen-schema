<<<<<<< Updated upstream
{
  lib,
  schemaLib,
  genLib,
  ...
}:
||||||| Stash base
{ lib, schemaLib, genLib, ... }:
=======
{
  lib,
  schemaLib,
  ...
}:
>>>>>>> Stashed changes
let
  inherit (schemaLib) mkSchemaOption;

  # Undeclared parent kind should throw
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
        eval.config.schema._meta.topology
      );
    in
    !result.success;

  # Multiple parents should throw (two kinds both claim the same child)
  throwsOnMultipleParents =
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
                config.schema.cluster = {
                  options.name = lib.mkOption { type = lib.types.str; };
                };
                # user declares parent = "host" in one module...
                config.schema.user = {
                  parent = "host";
                  options.shell = lib.mkOption { type = lib.types.str; };
                };
              }
              # ...and parent = "cluster" in another module (conflicting)
              {
                config.schema.user.parent = "cluster";
              }
            ];
          };
        in
        eval.config.schema._meta.topology
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
    test-multiple-parents-throws = {
      expr = throwsOnMultipleParents;
      expected = true;
    };
  };
}
