# nodeId: scope-engine canonical node identifier on instances.
{
  lib,
  schemaLib,
  genLib,
  ...
}:
let
  inherit (schemaLib) mkSchemaOption mkInstanceRegistry;

  eval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption { };
        options.hosts = mkInstanceRegistry config.schema "host" { };
        options.users = mkInstanceRegistry config.schema "user" { };
        config.schema.host = {
          options.addr = lib.mkOption {
            type = lib.types.str;
          };
        };
        config.schema.user = {
          options.shell = lib.mkOption {
            type = lib.types.str;
            default = "/bin/bash";
          };
        };
        config.hosts.igloo = {
          addr = "10.0.1.1";
        };
        config.hosts.iceberg = {
          addr = "10.0.2.1";
        };
        config.users.tux = { };
      }
    ];
  };
  config = eval.config;
in
{
  node-id = {
    # nodeId has canonical kind:name format
    test-host-node-id = {
      expr = config.hosts.igloo.nodeId;
      expected = "host:igloo";
    };

    test-host-node-id-second = {
      expr = config.hosts.iceberg.nodeId;
      expected = "host:iceberg";
    };

    test-user-node-id = {
      expr = config.users.tux.nodeId;
      expected = "user:tux";
    };

    # nodeId is different from id_hash (structural vs content identity)
    test-node-id-not-id-hash = {
      expr = config.hosts.igloo.nodeId != config.hosts.igloo.id_hash;
      expected = true;
    };

    # Different kinds with same instance name get different nodeIds
    test-node-id-kind-prefix = {
      expr = config.hosts.igloo.nodeId != config.users.tux.nodeId;
      expected = true;
    };
  };
}
