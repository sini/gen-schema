{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) evalSchema mkInstanceRegistry ref;

  schema = evalSchema {
    modules = [
      {
        config.schema.host = {
          options.addr = genMerge.mkOption { type = genMerge.types.str; };
        };
        config.schema.service = {
          options.host = genMerge.mkOption { type = ref "host"; };
        };
      }
    ];
  };

  # Missing refs binding should throw during evaluation.
  # We force evaluation of an instance to trigger the ref scan.
  throwsOnMissing =
    let
      result = builtins.tryEval (
        let
          eval = genMerge.evalModuleTree {
            modules = [
              {
                options.hosts = mkInstanceRegistry schema.host { };
                # No refs.host — should throw when service instances are evaluated
                options.services = mkInstanceRegistry schema.service { };
                config.hosts.igloo = {
                  addr = "10.0.1.1";
                };
                config.services.nginx = {
                  host = "igloo";
                };
              }
            ];
          };
        in
        # Force evaluation of the service registry to trigger ref scanning
        builtins.attrNames eval.config.services
      );
    in
    !result.success;
in
{
  flake.tests.ref-missing-binding = {
    test-missing-binding-throws = {
      expr = throwsOnMissing;
      expected = true;
    };
  };
}
