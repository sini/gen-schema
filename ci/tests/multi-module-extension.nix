{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) mkSchemaOption;

  # Three separate modules each extending schema.host with different options
  schemaEval = genMerge.evalModuleTree {
    modules = [
      {
        options.schema = mkSchemaOption { };
        config.schema.host = {
          options.name = genMerge.mkOption { type = genMerge.types.str; };
        };
      }
      {
        config.schema.host = {
          options.addr = genMerge.mkOption { type = genMerge.types.str; };
        };
      }
      {
        config.schema.host = {
          options.port = genMerge.mkOption {
            type = genMerge.types.int;
            default = 22;
          };
        };
      }
    ];
  };

  hostKind = schemaEval.config.schema.host;

  instance = genMerge.evalModuleTree {
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
  flake.tests.kind-extend.test-name-from-first-module = {
    expr = instance.config.name;
    expected = "igloo";
  };
  flake.tests.kind-extend.test-addr-from-second-module = {
    expr = instance.config.addr;
    expected = "10.0.0.1";
  };
  flake.tests.kind-extend.test-port-default-from-third-module = {
    expr = instance.config.port;
    expected = 22;
  };
  # Bare schema kinds don't have id_hash — see instance-identity.nix
  flake.tests.kind-extend.test-bare-kind-no-id-hash = {
    expr = instance.config ? id_hash;
    expected = false;
  };
}
