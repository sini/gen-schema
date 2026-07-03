{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) mkSchemaOption mkInstanceRegistry ref;

  eval = genMerge.evalModuleTree {
    modules = [
      {
        options.schema = mkSchemaOption { };
        options.hosts = mkInstanceRegistry eval.config.schema.host { };
        options.services = mkInstanceRegistry eval.config.schema.service {
          refs.hosts = eval.config.hosts;
          refs.primary = eval.config.hosts;
        };
        config.schema.host = {
          options.addr = genMerge.mkOption { type = genMerge.types.str; };
        };
        config.schema.service = {
          options.port = genMerge.mkOption { type = genMerge.types.int; };
          options.hosts = genMerge.mkOption {
            type = genMerge.types.listOf (ref "host");
            default = [ ];
          };
          options.primary = genMerge.mkOption {
            type = genMerge.types.nullOr (ref "host");
            default = null;
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
        config.services.nginx = {
          port = 80;
          hosts = [
            "igloo"
            "iceberg"
          ];
          primary = "igloo";
        };
        config.services.solo = {
          port = 443;
          # defaults: hosts = [], primary = null
        };
        config.services.mixed = {
          port = 8080;
          hosts = [
            "igloo"
            eval.config.hosts.iceberg
          ];
          primary = eval.config.hosts.igloo;
        };
      }
    ];
  };

  inherit (eval.config.services) nginx solo mixed;
in
{
  flake.tests.ref-listof = {
    test-listof-ref-string-coercion = {
      expr = map (h: h.addr) nginx.hosts;
      expected = [
        "10.0.1.1"
        "10.0.1.2"
      ];
    };
    test-listof-ref-mixed-coercion = {
      expr = map (h: h.addr) mixed.hosts;
      expected = [
        "10.0.1.1"
        "10.0.1.2"
      ];
    };
    test-listof-ref-empty = {
      expr = solo.hosts;
      expected = [ ];
    };
    test-nullor-deferred-ref-string = {
      expr = nginx.primary.addr;
      expected = "10.0.1.1";
    };
    test-nullor-deferred-ref-null = {
      expr = solo.primary;
      expected = null;
    };
    test-nullor-deferred-ref-instance = {
      expr = mixed.primary.addr;
      expected = "10.0.1.1";
    };
  };
}
