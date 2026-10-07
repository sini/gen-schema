{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) evalSchema mkInstanceRegistry declarationOf;

  schema = evalSchema { } [
    {
      config.schema.host = {
        options.addr = genMerge.mkOption { type = genMerge.types.str; };
      };
      config.schema.service = {
        options.host = genMerge.mkOption { type = declarationOf "host"; };
      };
    }
  ];

  # Missing refs binding should throw during evaluation.
  # We force evaluation of an instance to trigger the ref scan.
  throwsOnMissing =
    let
      result = builtins.tryEval (
        let
          eval = genMerge.evalModuleTree { } [
            {
              options.hosts = mkInstanceRegistry { } schema.host;
              # No refs.host — should throw when service instances are evaluated
              options.services = mkInstanceRegistry { } schema.service;
              config.hosts.igloo = {
                addr = "10.0.1.1";
              };
              config.services.nginx = {
                host = "igloo";
              };
            }
          ];
        in
        # Read an instance to trigger ref scanning: the name set is the definitions' (den-hoag-2vo1m)
        builtins.seq eval.config.services.nginx true
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
