# Codec — type-registered codecs with automatic wrapper traversal.
{ lib, schemaLib, ... }:
let
  inherit (schemaLib)
    mkSchemaOption
    mkInstanceRegistry
    mkCodec
    ref
    ;

  eval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption { };
        options.hosts = mkInstanceRegistry eval.config.schema.host { };
        options.services = mkInstanceRegistry eval.config.schema.service {
          refs.host = eval.config.hosts;
        };
        config.schema.host = {
          options.addr = lib.mkOption { type = lib.types.str; };
          options.port = lib.mkOption { type = lib.types.port; };
          options.optPort = lib.mkOption {
            type = lib.types.nullOr lib.types.port;
            default = null;
          };
          options.ports = lib.mkOption {
            type = lib.types.listOf lib.types.port;
            default = [ ];
          };
          options.labels = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = { };
          };
          options.role = lib.mkOption { type = lib.types.str; };
        };
        config.schema.service = {
          options.name = lib.mkOption { type = lib.types.str; };
          options.host = lib.mkOption { type = ref "host"; };
        };
        config.hosts.igloo = {
          addr = "10.0.1.1";
          port = 8080;
          optPort = 443;
          ports = [
            80
            443
            8080
          ];
          labels = {
            env = "prod";
            region = "us-east";
          };
          role = "web";
        };
        config.hosts.yurt = {
          addr = "10.0.1.2";
          port = 9090;
          role = "worker";
        };
        config.services.nginx = {
          host = "igloo";
        };
      }
    ];
  };

  # Codec with type-registered encoder for port
  portCodec = mkCodec eval.config.schema.host {
    types = {
      unsignedInt16 = {
        encode = v: "port:${toString v}";
        decode = v: lib.toInt (lib.removePrefix "port:" v);
      };
    };
  };

  # Codec with unused type (no fields of this type exist on host)
  unusedCodec = mkCodec eval.config.schema.host {
    types = {
      nonexistentType = {
        encode = v: v;
      };
    };
  };

  # Codec with per-field override suppressing type codec
  overrideCodec = mkCodec eval.config.schema.host {
    types = {
      unsignedInt16 = {
        encode = v: "port:${toString v}";
      };
    };
    fields = {
      port = {
        encode = v: "custom:${toString v}";
      };
    };
  };

  # Codec for service to test ref priority over types
  serviceCodec = mkCodec eval.config.schema.service {
    types = {
      # This should NOT apply to the host ref field
      str = {
        encode = v: "str:${v}";
      };
    };
  };

  igloo = eval.config.hosts.igloo;
  yurt = eval.config.hosts.yurt;
in
{
  flake.tests.codec-types = {
    # Direct type match
    test-type-encode-direct = {
      expr = (portCodec.encode igloo).port;
      expected = "port:8080";
    };
    test-type-decode-direct = {
      expr =
        (portCodec.decode {
          addr = "x";
          port = "port:8080";
          role = "w";
        }).port;
      expected = 8080;
    };

    # nullOr wrapper traversal
    test-type-nullor-value = {
      expr = (portCodec.encode igloo).optPort;
      expected = "port:443";
    };
    test-type-nullor-null = {
      expr = (portCodec.encode yurt).optPort;
      expected = null;
    };
    test-type-nullor-decode-null = {
      expr =
        (portCodec.decode {
          addr = "x";
          port = "port:9090";
          role = "w";
          optPort = null;
        }).optPort;
      expected = null;
    };

    # listOf wrapper traversal
    test-type-listof = {
      expr = (portCodec.encode igloo).ports;
      expected = [
        "port:80"
        "port:443"
        "port:8080"
      ];
    };
    test-type-listof-decode = {
      expr =
        (portCodec.decode {
          addr = "x";
          port = "port:8080";
          role = "w";
          ports = [ "port:80" ];
        }).ports;
      expected = [ 80 ];
    };

    # attrsOf — str has no registered codec, identity
    test-type-attrsof-identity = {
      expr = (portCodec.encode igloo).labels;
      expected = {
        env = "prod";
        region = "us-east";
      };
    };

    # Non-matching fields stay identity
    test-type-nonmatching-identity = {
      expr = (portCodec.encode igloo).addr;
      expected = "10.0.1.1";
    };

    # Unused type registration — no error
    test-unused-type-silent = {
      expr = (unusedCodec.encode igloo).addr;
      expected = "10.0.1.1";
    };

    # Per-field override suppresses type codec
    test-field-override-wins = {
      expr = (overrideCodec.encode igloo).port;
      expected = "custom:8080";
    };

    # Ref auto-detection takes priority over type registration
    test-ref-priority-over-type = {
      expr = (serviceCodec.encode eval.config.services.nginx).host;
      expected = "igloo";
    };
  };
}
