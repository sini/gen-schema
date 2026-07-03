# Codec — type-registered codecs with automatic wrapper traversal.
{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema)
    mkSchemaOption
    mkInstanceRegistry
    mkCodec
    ref
    ;

  eval = genMerge.evalModuleTree {
    modules = [
      {
        options.schema = mkSchemaOption { };
        options.hosts = mkInstanceRegistry eval.config.schema.host { };
        options.services = mkInstanceRegistry eval.config.schema.service {
          refs.host = eval.config.hosts;
        };
        config.schema.host = {
          options.addr = genMerge.mkOption { type = genMerge.types.str; };
          options.port = genMerge.mkOption { type = genMerge.types.int; };
          options.optPort = genMerge.mkOption {
            type = genMerge.types.nullOr genMerge.types.int;
            default = null;
          };
          options.ports = genMerge.mkOption {
            type = genMerge.types.listOf genMerge.types.int;
            default = [ ];
          };
          options.labels = genMerge.mkOption {
            type = genMerge.types.attrsOf genMerge.types.str;
            default = { };
          };
          options.role = genMerge.mkOption { type = genMerge.types.str; };
        };
        config.schema.service = {
          options.name = genMerge.mkOption { type = genMerge.types.str; };
          options.host = genMerge.mkOption { type = ref "host"; };
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

  # Codec with type-registered encoder for the (int-typed) port fields.
  # gen-merge/gen-types name the leaf "int" (nixpkgs' port alias "unsignedInt16" is gone);
  # the codec dispatches on `type.name`, so registrations key on "int".
  portCodec = mkCodec eval.config.schema.host {
    types = {
      int = {
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
      int = {
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
      # This should NOT apply to the host ref field ("string" is gen-types' str name)
      string = {
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
