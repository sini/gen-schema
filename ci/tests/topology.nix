{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) mkSchemaOption;

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
        config.schema.network = {
          options.cidr = genMerge.mkOption { type = genMerge.types.str; };
        };
      }
    ];
  };

  schema = eval.config.schema;
  topo = schema._topology;
in
{
  flake.tests.topology = {
    test-host-has-children = {
      expr = topo.host.children;
      expected = [ "user" ];
    };
    test-user-has-parent = {
      expr = topo.user.parent;
      expected = "host";
    };
    test-host-no-parent = {
      expr = topo.host.parent;
      expected = null;
    };
    test-network-no-relations = {
      expr = topo.network;
      expected = {
        parent = null;
        children = [ ];
      };
    };
    test-roots = {
      expr = schema._roots;
      expected = [
        "host"
        "network"
      ];
    };
    test-leaves = {
      expr = schema._leaves;
      expected = [
        "network"
        "user"
      ];
    };
  };
}
