{ lib, schemaLib, ... }:
let
  inherit (schemaLib) mkSchema schemaFn;

  eval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchema { };
        config.schema.host = {
          options.name = lib.mkOption { type = lib.types.str; };
          options.role = lib.mkOption { type = lib.types.str; };
          methods.describe = schemaFn "Describe this host" lib.types.str (
            { name, role, ... }: "${name} is a ${role}"
          );
        };
      }
    ];
  };

  hostKind = eval.config.schema.host;

  instance = lib.evalModules {
    modules = [
      hostKind
      {
        config.name = "igloo";
        config.role = "webserver";
      }
    ];
  };
in
{
  method-args.test-describe-resolves-name = {
    expr = instance.config.describe;
    expected = "igloo is a webserver";
  };
}
