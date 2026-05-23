{
  lib,
  schemaLib,
  genLib,
  ...
}:
let
  inherit (schemaLib) mkSchemaOption mkInstanceRegistry;

  schemaEval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption { };
        config.schema.service = {
          options.port = lib.mkOption { type = lib.types.int; };
          options.name = lib.mkOption { type = lib.types.str; };
        };
      }
    ];
  };

  schema = schemaEval.config.schema;

  validRegistry = mkInstanceRegistry schema "service" {
    refinements = {
      port = [
        {
          check = v: v > 0 && v < 65536;
          message = "must be valid port";
        }
      ];
    };
  };

  invalidRegistry = mkInstanceRegistry schema "service" {
    refinements = {
      port = [
        {
          check = v: v > 0;
          message = "must be positive";
        }
      ];
    };
  };

  validEval = lib.evalModules {
    modules = [
      {
        options.services = validRegistry;
        config.services.web = {
          port = 8080;
          name = "web";
        };
      }
    ];
  };

  invalidEval = lib.evalModules {
    modules = [
      {
        options.services = invalidRegistry;
        config.services.web = {
          port = -1;
          name = "web";
        };
      }
    ];
  };
in
{
  refined-pipeline.test-valid-instance-passes = {
    expr = validEval.config.services.web.port;
    expected = 8080;
  };

  refined-pipeline.test-invalid-instance-throws = {
    expr = builtins.tryEval (builtins.deepSeq invalidEval.config.services { });
    expected = {
      success = false;
      value = false;
    };
  };

  refined-pipeline.test-no-refinements-passthrough = {
    expr =
      let
        noRefRegistry = mkInstanceRegistry schema "service" { };
        eval = lib.evalModules {
          modules = [
            {
              options.services = noRefRegistry;
              config.services.web = {
                port = -1;
                name = "web";
              };
            }
          ];
        };
      in
      eval.config.services.web.port;
    expected = -1;
  };

  refined-pipeline.test-multiple-refinements-on-field = {
    expr =
      let
        multiRegistry = mkInstanceRegistry schema "service" {
          refinements = {
            port = [
              {
                check = v: v >= 1024;
                message = "must be >= 1024";
              }
              {
                check = v: v < 65536;
                message = "must be < 65536";
              }
            ];
          };
        };
        eval = lib.evalModules {
          modules = [
            {
              options.services = multiRegistry;
              config.services.web = {
                port = 8080;
                name = "web";
              };
            }
          ];
        };
      in
      eval.config.services.web.port;
    expected = 8080;
  };

  refined-pipeline.test-multiple-fields-refined = {
    expr =
      let
        multiFieldRegistry = mkInstanceRegistry schema "service" {
          refinements = {
            port = [
              {
                check = v: v > 0;
                message = "must be positive";
              }
            ];
            name = [
              {
                check = v: v != "";
                message = "must not be empty";
              }
            ];
          };
        };
        eval = lib.evalModules {
          modules = [
            {
              options.services = multiFieldRegistry;
              config.services.web = {
                port = 8080;
                name = "web";
              };
            }
          ];
        };
      in
      eval.config.services.web.name;
    expected = "web";
  };
}
