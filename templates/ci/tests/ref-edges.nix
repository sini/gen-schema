{
  lib,
  schemaLib,
  genLib,
  ...
}:
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
        config.schema.network = {
          options.cidr = lib.mkOption { type = lib.types.str; };
        };
      }
    ];
  };

  edges = eval.config.schema._meta.refEdges;
in
{
  ref-edges = {
    test-one-edge-found = {
      expr = builtins.length edges;
      expected = 1;
    };
    test-edge-from-service = {
      expr = (builtins.head edges).from;
      expected = "service";
    };
    test-edge-field-host = {
      expr = (builtins.head edges).field;
      expected = "host";
    };
    test-edge-to-host = {
      expr = (builtins.head edges).to;
      expected = "host";
    };
    test-no-edges-on-plain-kinds = {
      expr = builtins.length (builtins.filter (e: e.from == "network") edges);
      expected = 0;
    };
  };
}
