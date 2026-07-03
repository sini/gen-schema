{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) mkSchemaOption ref;

  eval = genMerge.evalModuleTree {
    modules = [
      {
        options.schema = mkSchemaOption { };
        config.schema.host = {
          options.addr = genMerge.mkOption { type = genMerge.types.str; };
        };
        config.schema.service = {
          options.port = genMerge.mkOption { type = genMerge.types.int; };
          options.host = genMerge.mkOption { type = ref "host"; };
        };
        # Kind with no refs
        config.schema.network = {
          options.cidr = genMerge.mkOption { type = genMerge.types.str; };
        };
      }
    ];
  };

  serviceKind = eval.config.schema.service;
  hostKind = eval.config.schema.host;
  networkKind = eval.config.schema.network;
in
{
  flake.tests.ref-introspection = {
    test-service-has-refs = {
      expr = serviceKind.refs ? host;
      expected = true;
    };
    test-service-ref-kind = {
      expr = serviceKind.refs.host.refKind;
      expected = "host";
    };
    test-service-ref-has-type = {
      expr = serviceKind.refs.host ? type;
      expected = true;
    };
    test-host-no-refs = {
      expr = hostKind.refs;
      expected = { };
    };
    test-network-no-refs = {
      expr = networkKind.refs;
      expected = { };
    };
  };
}
