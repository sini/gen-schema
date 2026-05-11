{ lib, schemaLib, ... }:
let
  inherit (schemaLib._internal) mkIdentityModule;
  mkEval =
    kind: modules:
    lib.evalModules {
      modules = [ (mkIdentityModule kind) ] ++ modules;
    };

  # identity=false excludes an option from reflection
  evalWithSecret = mkEval "host" [
    {
      options.name = lib.mkOption { type = lib.types.str; };
      options.secret = lib.mkOption { type = lib.types.str; } // {
        identity = false;
      };
    }
    {
      config.name = "igloo";
      config.secret = "s3cret";
    }
  ];
  evalWithDiffSecret = mkEval "host" [
    {
      options.name = lib.mkOption { type = lib.types.str; };
      options.secret = lib.mkOption { type = lib.types.str; } // {
        identity = false;
      };
    }
    {
      config.name = "igloo";
      config.secret = "different";
    }
  ];
  evalNameOnly = mkEval "host" [
    { options.name = lib.mkOption { type = lib.types.str; }; }
    { config.name = "igloo"; }
  ];

  # Internal options are also excluded from reflection
  evalWithInternal = mkEval "host" [
    {
      options.name = lib.mkOption { type = lib.types.str; };
      options.internal_val = lib.mkOption {
        type = lib.types.str;
        internal = true;
      };
    }
    {
      config.name = "igloo";
      config.internal_val = "hidden";
    }
  ];
in
{
  identity-optout.test-identity-false-excluded = {
    # Changing secret should not change hash
    expr = evalWithSecret.config.id_hash == evalWithDiffSecret.config.id_hash;
    expected = true;
  };
  identity-optout.test-identity-false-matches-without = {
    # Hash with identity=false secret should match hash without secret option
    expr = evalWithSecret.config.id_hash == evalNameOnly.config.id_hash;
    expected = true;
  };
  identity-optout.test-internal-excluded = {
    # Internal options excluded from reflection
    expr = evalWithInternal.config.id_hash == evalNameOnly.config.id_hash;
    expected = true;
  };
}
