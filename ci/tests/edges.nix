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
        config.schema.user = {
          parent = "host";
          options.shell = genMerge.mkOption { type = genMerge.types.str; };
        };
        config.schema.service = {
          options.port = genMerge.mkOption { type = genMerge.types.int; };
          options.host = genMerge.mkOption { type = ref "host"; };
        };
      }
    ];
  };

  edges = eval.config.schema._edges;
  parentEdges = builtins.filter (e: e.type == "parent") edges;
  refEdgesTyped = builtins.filter (e: e.type == "ref") edges;
in
{
  flake.tests.edges = {
    test-total-edge-count = {
      expr = builtins.length edges;
      expected = 2; # 1 parent (user→host) + 1 ref (service→host)
    };
    test-parent-edge = {
      expr = builtins.head parentEdges;
      expected = {
        from = "user";
        to = "host";
        type = "parent";
        field = null;
      };
    };
    test-ref-edge = {
      expr = builtins.head refEdgesTyped;
      expected = {
        from = "service";
        field = "host";
        to = "host";
        type = "ref";
      };
    };
  };
}
