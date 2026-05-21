# buildKindGraph / buildInstanceGraph: scope-engine bridge.
{ lib, schemaLib, genLib, ... }:
let
  inherit (schemaLib) mkSchemaOption mkInstanceRegistry ref buildKindGraph buildInstanceGraph;

  eval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption { };
        options.hosts = mkInstanceRegistry config.schema "host" { };
        options.services = mkInstanceRegistry config.schema "service" {
          refs.host = config.hosts;
        };
        config.schema.host = {
          options.addr = lib.mkOption { type = lib.types.str; };
          options.role = lib.mkOption {
            type = lib.types.str;
            default = "worker";
          };
        };
        config.schema.user = {
          options.shell = lib.mkOption {
            type = lib.types.str;
            default = "/bin/bash";
          };
        };
        config.schema.service = {
          options.port = lib.mkOption { type = lib.types.int; };
          options.host = lib.mkOption { type = ref "host"; };
        };
        config.schema._topology.host.children = [ "user" ];

        config.hosts.igloo = {
          addr = "10.0.1.1";
          role = "web";
        };
        config.hosts.iceberg = {
          addr = "10.0.2.1";
          role = "db";
        };
        config.services.nginx = {
          port = 80;
          host = "igloo";
        };
        config.services.postgres = {
          port = 5432;
          host = "iceberg";
        };
      }
    ];
  };
  config = eval.config;

  # ─── Kind-level graph ───────────────────────────────────────────

  kindGraph = buildKindGraph config.schema;

  # ─── Instance-level graph ───────────────────────────────────────

  fleet = {
    host = config.hosts;
    service = config.services;
    user = { }; # no users declared
  };
  instanceGraph = buildInstanceGraph config.schema fleet;
in
{
  scope-graph = {
    # ─── Kind graph: structure ────────────────────────────────────

    test-kind-vertices = {
      expr = builtins.sort builtins.lessThan kindGraph.parentGraph.vertices;
      expected = [ "host" "service" "user" ];
    };

    test-kind-parent-edges = {
      expr = kindGraph.parentGraph.edges;
      expected = [
        {
          from = "user";
          to = "host";
        }
      ];
    };

    test-kind-import-edges = {
      expr = kindGraph.importGraph.edges;
      expected = [
        {
          from = "service";
          to = "host";
        }
      ];
    };

    test-kind-decls-host = {
      expr = {
        inherit (kindGraph.decls.host) kind parent;
        children = kindGraph.decls.host.children;
      };
      expected = {
        kind = "host";
        parent = null;
        children = [ "user" ];
      };
    };

    test-kind-decls-user = {
      expr = {
        inherit (kindGraph.decls.user) kind parent;
      };
      expected = {
        kind = "user";
        parent = "host";
      };
    };

    test-kind-decls-service-refs = {
      expr = kindGraph.decls.service.refs;
      expected = {
        host = "host";
      };
    };

    test-kind-types = {
      expr = kindGraph.types;
      expected = {
        host = "kind";
        user = "kind";
        service = "kind";
      };
    };

    # ─── Instance graph: structure ────────────────────────────────

    test-instance-vertices = {
      expr = builtins.sort builtins.lessThan instanceGraph.parentGraph.vertices;
      expected = [ "host:iceberg" "host:igloo" "service:nginx" "service:postgres" ];
    };

    # Ref edges: service instances → host instances
    test-instance-import-edges = {
      expr = builtins.sort (a: b: a.from < b.from) instanceGraph.importGraph.edges;
      expected = [
        {
          from = "service:nginx";
          to = "host:igloo";
        }
        {
          from = "service:postgres";
          to = "host:iceberg";
        }
      ];
    };

    # Instance decls contain full instance config
    test-instance-decls-igloo-addr = {
      expr = instanceGraph.decls."host:igloo".addr;
      expected = "10.0.1.1";
    };

    test-instance-decls-nginx-port = {
      expr = instanceGraph.decls."service:nginx".port;
      expected = 80;
    };

    # Instance types carry kind name
    test-instance-types = {
      expr = {
        igloo = instanceGraph.types."host:igloo";
        nginx = instanceGraph.types."service:nginx";
      };
      expected = {
        igloo = "host";
        nginx = "service";
      };
    };

    # nodeId on instances matches graph node IDs
    test-node-id-matches-graph = {
      expr = config.hosts.igloo.nodeId == "host:igloo";
      expected = true;
    };

    # Ref resolution: nginx.host resolves to igloo instance
    test-ref-resolved = {
      expr = config.services.nginx.host.name;
      expected = "igloo";
    };

    test-ref-resolved-addr = {
      expr = config.services.nginx.host.addr;
      expected = "10.0.1.1";
    };
  };
}
