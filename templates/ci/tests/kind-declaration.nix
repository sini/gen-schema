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
  kind.test-kind-is-callable = {
    expr = builtins.isFunction (hostKind.__functor hostKind);
    expected = true;
  };
  kind.test-instance-name = {
    expr = instance.config.name;
    expected = "igloo";
  };
  kind.test-instance-addr = {
    expr = instance.config.addr;
    expected = "192.168.1.1";
  };
  kind.test-instance-has-id-hash = {
    expr = builtins.isString instance.config.id_hash;
    expected = true;
  };
  kind.test-id-hash-length = {
    expr = builtins.stringLength instance.config.id_hash;
    expected = 64;
  };
}
