{
  lib,
  schemaLib,
  genLib,
  ...
}:
let
  inherit (schemaLib) mkSchemaOption mkInstanceRegistry ref;

  # Missing refs binding should throw during evaluation.
  # We force evaluation of an instance to trigger the ref scan.
  throwsOnMissing =
    let
      result = builtins.tryEval (
        let
          eval = lib.evalModules {
            modules = [
              {
                options.schema = mkSchemaOption { };
                options.hosts = mkInstanceRegistry eval.config.schema "host" { };
                # No refs.host — should throw when service instances are evaluated
                options.services = mkInstanceRegistry eval.config.schema "service" { };
                config.schema.host = {
                  options.addr = lib.mkOption { type = lib.types.str; };
                };
                config.schema.service = {
                  options.host = lib.mkOption { type = ref "host"; };
                };
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
  ref-missing-binding = {
    test-missing-binding-throws = {
      expr = throwsOnMissing;
      expected = true;
    };
  };
}
