{ lib, schemaLib, ... }:
let
  inherit (schemaLib) mkSchemaOption;

  # Three separate modules each extending schema.host with different options
  schemaEval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption { };
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
  # Bare schema kinds don't have id_hash — see instance-identity.nix
  kind-extend.test-bare-kind-no-id-hash = {
    expr = instance.config ? id_hash;
    expected = false;
  };
}
