{ lib, schemaLib, ... }:
let
  inherit (schemaLib._internal) mkIdentityModule;
  mkEval =
    kind: modules:
    lib.evalModules {
      modules = [ (mkIdentityModule kind) ] ++ modules;
    };

  # _identity.keys overrides reflection when non-empty
  evalReflected = mkEval "host" [
    {
      options.name = lib.mkOption { type = lib.types.str; };
      options.role = lib.mkOption { type = lib.types.str; };
    }
    {
      config.name = "igloo";
      config.role = "web";
    }
  ];
  evalExplicitName = mkEval "host" [
    {
      options.name = lib.mkOption { type = lib.types.str; };
      options.role = lib.mkOption { type = lib.types.str; };
    }
    {
      config.name = "igloo";
      config.role = "web";
      config._identity.keys = [ "name" ];
    }
  ];
  evalExplicitNameOnly = mkEval "host" [
    {
      options.name = lib.mkOption { type = lib.types.str; };
      options.role = lib.mkOption { type = lib.types.str; };
    }
    {
      config.name = "igloo";
      config.role = "db"; # different role, but only name is identity key
      config._identity.keys = [ "name" ];
    }
  ];

  # Multiple modules contributing _identity.keys merge cleanly
  evalMerged = mkEval "host" [
    {
      options.name = lib.mkOption { type = lib.types.str; };
      options.role = lib.mkOption { type = lib.types.str; };
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
  identity-explicit.test-explicit-overrides-reflection = {
    expr = evalReflected.config.id_hash == evalExplicitName.config.id_hash;
    expected = false;
  };
  identity-explicit.test-explicit-ignores-other-options = {
    expr = evalExplicitName.config.id_hash == evalExplicitNameOnly.config.id_hash;
    expected = true;
  };
  identity-explicit.test-merged-keys = {
    # Merged keys = ["name" "role"], same as reflection for this schema
    expr = evalMerged.config.id_hash == evalReflected.config.id_hash;
    expected = true;
  };
}
