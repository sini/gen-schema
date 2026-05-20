{ lib, schemaLib, genLib, ... }:
let
  inherit (schemaLib) mkSchemaOption ref;

  eval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption { };
        config.schema.host = {
          options.addr = lib.mkOption { type = lib.types.str; };
        };
        config.schema.service = {
          options.port = lib.mkOption { type = lib.types.int; };
          options.host = lib.mkOption { type = ref "host"; };
        };
        # Kind with no refs
        config.schema.network = {
          options.cidr = lib.mkOption { type = lib.types.str; };
        };
      }
    ];
  };

  serviceMeta = eval.config.schema._meta.kindMeta "service";
  hostMeta = eval.config.schema._meta.kindMeta "host";
  networkMeta = eval.config.schema._meta.kindMeta "network";
in
{
  ref-introspection = {
    test-service-has-refs = {
      expr = serviceMeta.refs;
      expected = { host = "host"; };
    };
    test-host-no-refs = {
      expr = hostMeta.refs;
      expected = { };
    };
    test-network-no-refs = {
      expr = networkMeta.refs;
      expected = { };
    };
  };
}
