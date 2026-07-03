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
        config.schema.network = {
          options.cidr = genMerge.mkOption { type = genMerge.types.str; };
        };
      }
    ];
  };

  edges = eval.config.schema._refEdges;
in
{
  flake.tests.ref-edges = {
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
