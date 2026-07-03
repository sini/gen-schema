{
  lib,
  genSchema,
  genMerge,
  genAlgebra,
  ...
}:
let
  inherit (genSchema) mkSchemaOption mkInstanceRegistry;

  schemaEval = genMerge.evalModuleTree {
    modules = [
      {
        options.schema = mkSchemaOption { };
        config.schema.service = {
          options.port = genMerge.mkOption { type = genMerge.types.int; };
          options.name = genMerge.mkOption { type = genMerge.types.str; };
        };
      }
    ];
  };

  schema = schemaEval.config.schema;

  lazyRegistry = mkInstanceRegistry schema.service {
    refinements = {
      port = [
        {
          check = v: v > 0;
          message = "must be positive";
          lazy = true;
        }
      ];
    };
  };

  eval = genMerge.evalModuleTree {
    modules = [
      {
        options.services = lazyRegistry;
        config.services.web = {
          port = -1;
          name = "web";
        };
      }
    ];
  };
in
{
  # Lazy contract: non-refined fields remain accessible without triggering the contract
  flake.tests.lazy-contract.test-instance-accessible = {
    expr = eval.config.services.web.name;
    expected = "web";
  };

  # Lazy contract: accessing the refined field triggers the contract violation
  flake.tests.lazy-contract.test-lazy-field-throws-on-access = {
    expr = builtins.tryEval (builtins.deepSeq eval.config.services.web.port "ok");
    expected = {
      success = false;
      value = false;
    };
  };

  # Lazy contract with valid value: no throw
  flake.tests.lazy-contract.test-lazy-valid-passes = {
    expr =
      let
        validEval = genMerge.evalModuleTree {
          modules = [
            {
              options.services = lazyRegistry;
              config.services.web = {
                port = 8080;
                name = "web";
              };
            }
          ];
        };
      in
      validEval.config.services.web.port;
    expected = 8080;
  };

  # Mixed: strict and lazy refinements on different fields
  flake.tests.lazy-contract.test-mixed-strict-and-lazy = {
    expr =
      let
        mixedRegistry = mkInstanceRegistry schema.service {
          refinements = {
            port = [
              {
                check = v: v > 0;
                message = "must be positive";
                lazy = true;
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
        mixedEval = genMerge.evalModuleTree {
          modules = [
            {
              options.services = mixedRegistry;
              config.services.web = {
                port = 8080;
                name = "web";
              };
            }
          ];
        };
      in
      mixedEval.config.services.web.port;
    expected = 8080;
  };
}
