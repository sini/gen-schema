{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) evalSchema mkSchemaOption mkInstanceRegistry;

  schema = evalSchema {
    schemaOption = mkSchemaOption {
      strict = true;
      collections.tags = {
        default = [ ];
      };
    };
    modules = [
      {
        config.schema.host = {
          options.name = genMerge.mkOption { type = genMerge.types.str; };
          tags = [ "server" ];
        };
      }
    ];
  };

  eval = genMerge.evalModuleTree {
    modules = [
      {
        options.hosts = mkInstanceRegistry schema.host { };
        config.hosts.igloo = {
          name = "igloo";
        };
      }
    ];
  };

  # If tags leaked into the module merge, strict mode would reject it
  result = builtins.tryEval (builtins.deepSeq eval.config.hosts.igloo eval.config.hosts.igloo);
in
{
  flake.tests.collection-strip.test-no-leak-in-strict = {
    expr = result.success;
    expected = true;
  };
}
