{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) mkIdentityModule;
  mkEval =
    kind: modules:
    genMerge.evalModuleTree {
      modules = [ (mkIdentityModule kind) ] ++ modules;
    };

  evalReflected = mkEval "host" [
    {
      options.name = genMerge.mkOption { type = genMerge.types.str; };
      options.role = genMerge.mkOption { type = genMerge.types.str; };
    }
    {
      config.name = "igloo";
      config.role = "web";
    }
  ];
  evalExplicitName = mkEval "host" [
    {
      options.name = genMerge.mkOption { type = genMerge.types.str; };
      options.role = genMerge.mkOption { type = genMerge.types.str; };
    }
    {
      config.name = "igloo";
      config.role = "web";
      config._identity.keys = [ "name" ];
    }
  ];
  evalExplicitNameOnly = mkEval "host" [
    {
      options.name = genMerge.mkOption { type = genMerge.types.str; };
      options.role = genMerge.mkOption { type = genMerge.types.str; };
    }
    {
      config.name = "igloo";
      config.role = "db";
      config._identity.keys = [ "name" ];
    }
  ];
  evalMerged = mkEval "host" [
    {
      options.name = genMerge.mkOption { type = genMerge.types.str; };
      options.role = genMerge.mkOption { type = genMerge.types.str; };
    }
    { config._identity.keys = [ "name" ]; }
    { config._identity.keys = [ "role" ]; }
    {
      config.name = "igloo";
      config.role = "web";
    }
  ];
in
{
  flake.tests.identity-explicit.test-explicit-overrides-reflection = {
    expr = evalReflected.config.id_hash == evalExplicitName.config.id_hash;
    expected = false;
  };
  flake.tests.identity-explicit.test-explicit-ignores-other-options = {
    expr = evalExplicitName.config.id_hash == evalExplicitNameOnly.config.id_hash;
    expected = true;
  };
  flake.tests.identity-explicit.test-merged-keys = {
    expr = evalMerged.config.id_hash == evalReflected.config.id_hash;
    expected = true;
  };
}
