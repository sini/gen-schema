{
  lib,
  schemaLib,
  ...
}:
let
  inherit (schemaLib) mkSchemaOption mkInstanceRegistry ref;

  eval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption { };
        options.hosts = mkInstanceRegistry eval.config.schema.host { };
        options.services = mkInstanceRegistry eval.config.schema.service {
          refs.hosts = eval.config.hosts;
          refs.primary = eval.config.hosts;
        };
        config.schema.host = {
          options.addr = lib.mkOption { type = lib.types.str; };
        };
        config.schema.service = {
          options.port = lib.mkOption { type = lib.types.int; };
          options.hosts = lib.mkOption {
            type = lib.types.nullOr (lib.types.listOf (ref "host"));
            default = null;
          };
          options.primary = lib.mkOption {
            type = lib.types.listOf (lib.types.nullOr (ref "host"));
            default = [ ];
          };
        };
        config.hosts = {
          igloo = {
            addr = "10.0.1.1";
          };
          iceberg = {
            addr = "10.0.1.2";
          };
        };
        config.services.web = {
          port = 80;
          hosts = [
            "igloo"
            "iceberg"
          ];
          primary = [
            "igloo"
            null
            "iceberg"
          ];
        };
        config.services.empty = {
          port = 443;
        };
        config.services.instance-vals = {
          port = 8080;
          hosts = [
            eval.config.hosts.igloo
            "iceberg"
          ];
          primary = [
            eval.config.hosts.igloo
            null
          ];
        };
      }
    ];
  };

  inherit (eval.config.services) web empty;
  instance-vals = eval.config.services.instance-vals;
in
{
  flake.tests.ref-nested-wrappers = {
    test-nullor-listof-ref-strings = {
      expr = map (h: h.addr) web.hosts;
      expected = [
        "10.0.1.1"
        "10.0.1.2"
      ];
    };
    test-nullor-listof-ref-null = {
      expr = empty.hosts;
      expected = null;
    };
    test-listof-nullor-ref-with-nulls = {
      expr = map (h: if h == null then "none" else h.addr) web.primary;
      expected = [
        "10.0.1.1"
        "none"
        "10.0.1.2"
      ];
    };
    test-nullor-listof-ref-mixed-instances = {
      expr = map (h: h.addr) instance-vals.hosts;
      expected = [
        "10.0.1.1"
        "10.0.1.2"
      ];
    };
    test-listof-nullor-ref-instance-and-null = {
      expr = map (h: if h == null then "none" else h.addr) instance-vals.primary;
      expected = [
        "10.0.1.1"
        "none"
      ];
    };
  };
}
