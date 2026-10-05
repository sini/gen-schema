{
  lib,
  genSchema,
  genMerge,
  genAlgebra,
  ...
}:
let
  inherit (genSchema) mkSchemaOption mkInstanceRegistry;

  schemaEval = genMerge.evalModuleTree { } [
    {
      options.schema = mkSchemaOption { };
      config.schema.service = {
        options.port = genMerge.mkOption { type = genMerge.types.int; };
        options.name = genMerge.mkOption { type = genMerge.types.str; };
      };
    }
  ];

  schema = schemaEval.config.schema;

  validRegistry = mkInstanceRegistry {
    refinements = {
      port = [
        {
          check = v: v > 0 && v < 65536;
          message = "must be valid port";
        }
      ];
    };
  } schema.service;

  invalidRegistry = mkInstanceRegistry {
    refinements = {
      port = [
        {
          check = v: v > 0;
          message = "must be positive";
        }
      ];
    };
  } schema.service;

  validEval = genMerge.evalModuleTree { } [
    {
      options.services = validRegistry;
      config.services.web = {
        port = 8080;
        name = "web";
      };
    }
  ];

  invalidEval = genMerge.evalModuleTree { } [
    {
      options.services = invalidRegistry;
      config.services.web = {
        port = -1;
        name = "web";
      };
    }
  ];
in
{
  flake.tests.refined-pipeline.test-valid-instance-passes = {
    expr = validEval.config.services.web.port;
    expected = 8080;
  };

  flake.tests.refined-pipeline.test-invalid-instance-throws = {
    expr = builtins.tryEval (builtins.deepSeq invalidEval.config.services { });
    expected = {
      success = false;
      value = false;
    };
  };

  flake.tests.refined-pipeline.test-no-refinements-passthrough = {
    expr =
      let
        noRefRegistry = mkInstanceRegistry { } schema.service;
        eval = genMerge.evalModuleTree { } [
          {
            options.services = noRefRegistry;
            config.services.web = {
              port = -1;
              name = "web";
            };
          }
        ];
      in
      eval.config.services.web.port;
    expected = -1;
  };

  flake.tests.refined-pipeline.test-multiple-refinements-on-field = {
    expr =
      let
        multiRegistry = mkInstanceRegistry {
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
        } schema.service;
        eval = genMerge.evalModuleTree { } [
          {
            options.services = multiRegistry;
            config.services.web = {
              port = 8080;
              name = "web";
            };
          }
        ];
      in
      eval.config.services.web.port;
    expected = 8080;
  };

  flake.tests.refined-pipeline.test-multiple-fields-refined = {
    expr =
      let
        multiFieldRegistry = mkInstanceRegistry {
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
        } schema.service;
        eval = genMerge.evalModuleTree { } [
          {
            options.services = multiFieldRegistry;
            config.services.web = {
              port = 8080;
              name = "web";
            };
          }
        ];
      in
      eval.config.services.web.name;
    expected = "web";
  };
}
