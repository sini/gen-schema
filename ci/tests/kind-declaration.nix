{ lib, schemaLib, ... }:
let
  inherit (schemaLib) mkSchemaOption;

  # Declare a schema with a "host" kind
  schemaEval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption { };
        config.schema.host = {
          options.name = lib.mkOption { type = lib.types.str; };
          options.addr = lib.mkOption { type = lib.types.str; };
        };
      }
    ];
  };

  hostKind = schemaEval.config.schema.host;

  # Import the kind into an instance evaluation
  instance = lib.evalModules {
    modules = [
      hostKind
      {
        config.name = "igloo";
        config.addr = "192.168.1.1";
      }
    ];
  };
in
{
  flake.tests.kind.test-kind-is-callable = {
    expr = builtins.isFunction (hostKind.__functor hostKind);
    expected = true;
  };
  flake.tests.kind.test-instance-name = {
    expr = instance.config.name;
    expected = "igloo";
  };
  flake.tests.kind.test-instance-addr = {
    expr = instance.config.addr;
    expected = "192.168.1.1";
  };
  # Bare schema kinds don't have id_hash — that's an instance-level concern.
  # See instance-identity.nix for instance-level identity tests.
  flake.tests.kind.test-bare-kind-no-id-hash = {
    expr = instance.config ? id_hash;
    expected = false;
  };
}
