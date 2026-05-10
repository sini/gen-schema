{ lib, schemaLib, ... }:
let
  inherit (schemaLib) mkSchema;

  # Three separate modules each extending schema.host with different options
  schemaEval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchema { };
        config.schema.host = {
          options.name = lib.mkOption { type = lib.types.str; };
        };
      }
      {
        config.schema.host = {
          options.addr = lib.mkOption { type = lib.types.str; };
        };
      }
      {
        config.schema.host = {
          options.port = lib.mkOption {
            type = lib.types.int;
            default = 22;
          };
        };
      }
    ];
  };

  hostKind = schemaEval.config.schema.host;

  instance = lib.evalModules {
    modules = [
      hostKind
      {
        config.name = "igloo";
        config.addr = "10.0.0.1";
      }
    ];
  };
in
{
  kind-extend.test-name-from-first-module = {
    expr = instance.config.name;
    expected = "igloo";
  };
  kind-extend.test-addr-from-second-module = {
    expr = instance.config.addr;
    expected = "10.0.0.1";
  };
  kind-extend.test-port-default-from-third-module = {
    expr = instance.config.port;
    expected = 22;
  };
  kind-extend.test-has-id-hash = {
    expr = builtins.isString instance.config.id_hash;
    expected = true;
  };
}
