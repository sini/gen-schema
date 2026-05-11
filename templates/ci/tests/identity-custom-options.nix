{ lib, schemaLib, ... }:
let
  inherit (schemaLib._internal) mkIdentityModule;
  mkEval =
    kind: modules:
    lib.evalModules {
      modules = [ (mkIdentityModule kind) ] ++ modules;
    };

  # Custom schema options are auto-included in id_hash via reflection
  evalWithRole = mkEval "host" [
    {
      options.name = lib.mkOption { type = lib.types.str; };
      options.role = lib.mkOption { type = lib.types.str; };
    }
    {
      config.name = "igloo";
      config.role = "web";
    }
  ];
  evalWithDiffRole = mkEval "host" [
    {
      options.name = lib.mkOption { type = lib.types.str; };
      options.role = lib.mkOption { type = lib.types.str; };
    }
    {
      config.name = "igloo";
      config.role = "db";
    }
  ];
  evalWithoutRole = mkEval "host" [
    { options.name = lib.mkOption { type = lib.types.str; }; }
    { config.name = "igloo"; }
  ];

  # Int and bool options are also reflected
  evalWithInt = mkEval "host" [
    {
      options.name = lib.mkOption { type = lib.types.str; };
      options.port = lib.mkOption { type = lib.types.int; };
    }
    {
      config.name = "igloo";
      config.port = 8080;
    }
  ];
  evalWithBool = mkEval "host" [
    {
      options.name = lib.mkOption { type = lib.types.str; };
      options.enabled = lib.mkOption { type = lib.types.bool; };
    }
    {
      config.name = "igloo";
      config.enabled = true;
    }
  ];
in
{
  identity-custom.test-custom-option-changes-hash = {
    expr = evalWithRole.config.id_hash == evalWithDiffRole.config.id_hash;
    expected = false;
  };
  identity-custom.test-extra-option-changes-hash = {
    expr = evalWithRole.config.id_hash == evalWithoutRole.config.id_hash;
    expected = false;
  };
  identity-custom.test-int-option-reflected = {
    expr = evalWithInt.config.id_hash != evalWithoutRole.config.id_hash;
    expected = true;
  };
  identity-custom.test-bool-option-reflected = {
    expr = evalWithBool.config.id_hash != evalWithoutRole.config.id_hash;
    expected = true;
  };
}
