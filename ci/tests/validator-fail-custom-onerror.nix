{
  lib,
  schemaLib,
  genLib,
  ...
}:
let
  eval = lib.evalModules {
    modules = [
      {
        options.schema = schemaLib.mkSchemaOption { };
        options.hosts = schemaLib.mkInstanceRegistry eval.config.schema.host {
          extraModules = [
            {
              options.tag = lib.mkOption {
                type = lib.types.str;
                default = "fallback";
                internal = true;
              };
            }
          ];
          deriveEither = {
            derive = instances: { right = lib.mapAttrs (name: _: { tag = "derived-${name}"; }) instances; };
            onError = _: { };
          };
        };
        config.schema.host = {
          options.addr = lib.mkOption { type = lib.types.str; };
          validators = [
            (genLib.mkValidator "always-fail" (_: false) "always fails")
          ];
        };
        config.hosts.igloo.addr = "10.0.1.1";
      }
    ];
  };
in
{
  flake.tests."validator-custom-error" = {
    test-no-throw = {
      expr =
        (builtins.tryEval (builtins.deepSeq eval.config.hosts.igloo.addr eval.config.hosts.igloo.addr))
        .success;
      expected = true;
    };
    # After recovery, derive still runs — tag gets the derived value
    test-derive-runs-after-recovery = {
      expr = eval.config.hosts.igloo.tag;
      expected = "derived-igloo";
    };
  };
}
