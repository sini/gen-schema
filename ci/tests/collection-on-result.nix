{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) mkSchemaOption;

  eval = genMerge.evalModuleTree {
    modules = [
      {
        options.schema = mkSchemaOption {
          collections.includes = {
            default = [ ];
          };
          collections.excludes = {
            default = [ ];
          };
        };
        config.schema.host = {
          options.name = genMerge.mkOption { type = genMerge.types.str; };
          includes = [ "networking" ];
          excludes = [ "desktop" ];
        };
      }
    ];
  };

  hostKind = eval.config.schema.host;
in
{
  flake.tests.collection-result.test-includes-on-kind = {
    expr = hostKind.includes;
    expected = [ "networking" ];
  };
  flake.tests.collection-result.test-excludes-on-kind = {
    expr = hostKind.excludes;
    expected = [ "desktop" ];
  };
  flake.tests.collection-result.test-still-callable = {
    expr = builtins.isFunction (hostKind.__functor hostKind);
    expected = true;
  };
}
