{ lib, schemaLib, ... }:
let
  inherit (schemaLib) mkSchemaOption;

  eval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption {
          sidecars.includes = {
            default = [ ];
          };
          sidecars.excludes = {
            default = [ ];
          };
        };
        config.schema.host = {
          options.name = lib.mkOption { type = lib.types.str; };
          includes = [ "networking" ];
          excludes = [ "desktop" ];
        };
      }
    ];
  };

  hostKind = eval.config.schema.host;
in
{
  sidecar-result.test-includes-on-kind = {
    expr = hostKind.includes;
    expected = [ "networking" ];
  };
  sidecar-result.test-excludes-on-kind = {
    expr = hostKind.excludes;
    expected = [ "desktop" ];
  };
  sidecar-result.test-still-callable = {
    expr = builtins.isFunction (hostKind.__functor hostKind);
    expected = true;
  };
}
