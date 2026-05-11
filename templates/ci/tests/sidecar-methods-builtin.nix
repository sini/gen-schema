{ lib, schemaLib, ... }:
let
  inherit (schemaLib) mkSchemaOption schemaFn;

  eval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption {
          sidecars.tags = {
            default = [ ];
          };
        };
        config.schema.host = {
          options.name = lib.mkOption { type = lib.types.str; };
          tags = [ "server" ];
          methods.label = schemaFn "Label" lib.types.str ({ name, ... }: "host:${name}");
        };
      }
    ];
  };

  hostKind = eval.config.schema.host;

  instance = lib.evalModules {
    modules = [
      hostKind
      { config.name = "igloo"; }
    ];
  };
in
{
  sidecar-methods.test-method-works = {
    expr = instance.config.label;
    expected = "host:igloo";
  };
  sidecar-methods.test-sidecar-on-kind = {
    expr = hostKind.tags;
    expected = [ "server" ];
  };
}
