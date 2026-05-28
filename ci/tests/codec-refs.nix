{
  lib,
  schemaLib,
  ...
}:
let
  inherit (schemaLib)
    mkSchemaOption
    mkInstanceRegistry
    mkCodec
    ref
    setOf
    ;

  eval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption { };
        options.hosts = mkInstanceRegistry eval.config.schema "host" { };
        options.services = mkInstanceRegistry eval.config.schema "service" {
          refs.host = eval.config.hosts;
          refs.replicas = eval.config.hosts;
          refs.primary = eval.config.hosts;
          refs.backends = eval.config.hosts;
        };
        config.schema.host = {
          options.addr = lib.mkOption { type = lib.types.str; };
        };
        config.schema.service = {
          options.port = lib.mkOption { type = lib.types.int; };
          options.host = lib.mkOption { type = ref "host"; };
          options.replicas = lib.mkOption {
            type = lib.types.listOf (ref "host");
            default = [ ];
          };
          options.primary = lib.mkOption {
            type = lib.types.nullOr (ref "host");
            default = null;
          };
          options.backends = lib.mkOption {
            type = setOf (ref "host");
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
        config.services.nginx = {
          port = 80;
          host = "igloo";
          replicas = [
            "igloo"
            "iceberg"
          ];
          primary = "igloo";
          backends = [
            "igloo"
            "iceberg"
            "igloo"
          ];
        };
        config.services.solo = {
          port = 443;
          host = "iceberg";
        };
      }
    ];
  };

  codec = mkCodec {
    schema = eval.config.schema;
    kind = "service";
  };

  encoded = codec.encode eval.config.services.nginx;
  encodedSolo = codec.encode eval.config.services.solo;
in
{
  flake.tests.codec-refs = {
    test-scalar-ref-encodes-name = {
      expr = encoded.host;
      expected = "igloo";
    };
    test-listof-ref-encodes-names = {
      expr = encoded.replicas;
      expected = [
        "igloo"
        "iceberg"
      ];
    };
    test-nullor-ref-encodes-name = {
      expr = encoded.primary;
      expected = "igloo";
    };
    test-nullor-ref-null = {
      expr = encodedSolo.primary;
      expected = null;
    };
    test-setof-ref-encodes-names = {
      expr = builtins.sort (a: b: a < b) encoded.backends;
      expected = [
        "iceberg"
        "igloo"
      ];
    };
    test-ref-decode-identity = {
      expr = codec.decode {
        port = 80;
        host = "igloo";
        replicas = [ "igloo" ];
        primary = null;
        backends = [ ];
      };
      expected = {
        port = 80;
        host = "igloo";
        replicas = [ "igloo" ];
        primary = null;
        backends = [ ];
      };
    };
  };
}
