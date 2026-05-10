{ lib, schemaLib, ... }:
let
  # Spike: does a custom `identity = false` attribute survive evalModules?
  eval = lib.evalModules {
    modules = [
      {
        options.name = lib.mkOption { type = lib.types.str; };
        options.secret = lib.mkOption { type = lib.types.str; } // {
          identity = false;
        };
      }
      {
        config.name = "test";
        config.secret = "s3cret";
      }
    ];
  };
  secretOpt = eval.options.secret;
  survives = secretOpt ? identity && secretOpt.identity == false;
in
{
  identity-spike.test-custom-attr-survives = {
    expr = survives;
    expected = true;
  };
}
