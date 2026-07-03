{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) mkSchemaOption;

  # mkSchemaOption with a baseModule that adds a description option
  schemaEval = genMerge.evalModuleTree {
    modules = [
      {
        options.schema = mkSchemaOption {
          baseModule = {
            options.description = genMerge.mkOption {
              type = genMerge.types.str;
              default = "no description";
            };
          };
        };
        config.schema.host = {
          options.name = genMerge.mkOption { type = genMerge.types.str; };
        };
        config.schema.user = {
          options.email = genMerge.mkOption { type = genMerge.types.str; };
        };
      }
    ];
  };

  hostInstance = genMerge.evalModuleTree {
    modules = [
      schemaEval.config.schema.host
      {
        config.name = "igloo";
        config.description = "a frosty host";
      }
    ];
  };

  userInstance = genMerge.evalModuleTree {
    modules = [
      schemaEval.config.schema.user
      {
        config.email = "yeti@snow.land";
      }
    ];
  };
in
{
  flake.tests.base.test-host-has-base-option = {
    expr = hostInstance.config.description;
    expected = "a frosty host";
  };
  flake.tests.base.test-user-has-base-default = {
    expr = userInstance.config.description;
    expected = "no description";
  };
  flake.tests.base.test-host-own-option = {
    expr = hostInstance.config.name;
    expected = "igloo";
  };
  flake.tests.base.test-user-own-option = {
    expr = userInstance.config.email;
    expected = "yeti@snow.land";
  };
}
