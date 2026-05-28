{
  lib,
  schemaLib,
  genLib,
  ...
}:
let
  inherit (schemaLib) mkSchemaOption mkInstanceRegistry renderDocs;
  inherit (genLib) mkRefType;

  # Empty schema — zero kinds
  emptyEval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption { };
      }
    ];
  };

  # Docs default rendering
  docsEval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption { };
        config.schema.host = {
          options.name = lib.mkOption { type = lib.types.str; };
          options.port = lib.mkOption {
            type = lib.types.int;
            default = 80;
          };
          options.role = lib.mkOption {
            type = lib.types.str;
            default = "worker";
          };
        };
      }
    ];
  };
  docs = renderDocs docsEval.config.schema;

  # mkRefType with two modules setting same ref to different values
  refConflictEval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption { };
        options.hosts = mkInstanceRegistry refConflictEval.config.schema.host { };
        options.services = mkInstanceRegistry refConflictEval.config.schema.service {
          extraModules = [
            (
              { ... }:
              {
                options.host = lib.mkOption {
                  type = mkRefType refConflictEval.config.hosts;
                };
              }
            )
          ];
        };
        config.schema.host.options.addr = lib.mkOption { type = lib.types.str; };
        config.schema.service.options.port = lib.mkOption { type = lib.types.int; };
        config.hosts.igloo.addr = "10.0.1.1";
        config.hosts.iceberg.addr = "10.0.1.2";
      }
      # Two modules set the same service's host to different values
      {
        config.services.nginx = {
          host = "igloo";
          port = 80;
        };
      }
      { config.services.nginx.host = "iceberg"; }
    ];
  };
  refConflict = builtins.tryEval (
    builtins.deepSeq refConflictEval.config.services.nginx.host refConflictEval.config.services.nginx.host
  );
in
{
  flake.tests."edge-cases".test-empty-schema-kind-names = {
    expr = emptyEval.config.schema._kindNames;
    expected = [ ];
  };
  flake.tests."edge-cases".test-empty-schema-docs = {
    expr = renderDocs emptyEval.config.schema;
    expected = "";
  };
  flake.tests."edge-cases".test-docs-shows-default-value = {
    expr = lib.hasInfix "worker" docs;
    expected = true;
  };
  flake.tests."edge-cases".test-docs-shows-int-default = {
    expr = lib.hasInfix "80" docs;
    expected = true;
  };
  # mergeOneOption should reject conflicting ref defs
  flake.tests."edge-cases".test-ref-conflict-throws = {
    expr = refConflict.success;
    expected = false;
  };
}
