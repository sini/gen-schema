{ lib, schemaLib, genLib, ... }:
let
  inherit (schemaLib) mkSchemaOption;

  # Undeclared child kind should throw
  throwsOnUnknownChild =
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
                config.schema._topology.host.children = [ "nonexistent" ];
              }
            ];
          };
        in
        eval.config.schema._meta.topology
      );
    in
    !result.success;

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
                config.schema._topology.ghost.children = [ "host" ];
              }
            ];
          };
        in
        eval.config.schema._meta.topology
      );
    in
    !result.success;

  # Multiple parents should throw
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
                config.schema.user = {
                  options.shell = lib.mkOption { type = lib.types.str; };
                };
                config.schema._topology.host.children = [ "user" ];
                config.schema._topology.cluster.children = [ "user" ];
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
    test-unknown-child-throws = {
      expr = throwsOnUnknownChild;
      expected = true;
    };
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
