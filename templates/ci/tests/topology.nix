{
  lib,
  schemaLib,
  genLib,
  ...
}:
let
  inherit (schemaLib) mkSchemaOption;

  eval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption { };
        config.schema.host = {
          options.addr = lib.mkOption { type = lib.types.str; };
        };
        config.schema.user = {
          options.shell = lib.mkOption { type = lib.types.str; };
        };
        config.schema.network = {
          options.cidr = lib.mkOption { type = lib.types.str; };
        };
        config.schema._topology.host.children = [ "user" ];
      }
    ];
  };

  meta = eval.config.schema._meta;
  topo = meta.topology;
in
{
  topology = {
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
      expr = meta.roots;
      expected = [
        "host"
        "network"
      ];
    };
    test-leaves = {
      expr = meta.leaves;
      expected = [
        "network"
        "user"
      ];
    };
  };
}
