{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema)
    evalSchema
    mkInstanceRegistry
    mkCodec
    declarationOf
    setOf
    ;

  schema = evalSchema { } [
    {
      config.schema.host = {
        options.addr = genMerge.mkOption { type = genMerge.types.str; };
      };
      config.schema.service = {
        options.port = genMerge.mkOption { type = genMerge.types.int; };
        options.host = genMerge.mkOption { type = declarationOf "host"; };
        options.replicas = genMerge.mkOption {
          type = genMerge.types.listOf (declarationOf "host");
          default = [ ];
        };
        options.primary = genMerge.mkOption {
          type = genMerge.types.nullOr (declarationOf "host");
          default = null;
        };
        options.backends = genMerge.mkOption {
          type = setOf (declarationOf "host");
          default = [ ];
        };
        options.byName = genMerge.mkOption {
          type = genMerge.types.attrsOf (declarationOf "host");
          default = { };
        };
        options.byNameLazy = genMerge.mkOption {
          type = genMerge.types.lazyAttrsOf (declarationOf "host");
          default = { };
        };
      };
    }
  ];

  eval = genMerge.evalModuleTree { } [
    {
      options.hosts = mkInstanceRegistry { } schema.host;
      options.services = mkInstanceRegistry {
        refs.host = eval.config.hosts;
        refs.replicas = eval.config.hosts;
        refs.primary = eval.config.hosts;
        refs.backends = eval.config.hosts;
        refs.byName = eval.config.hosts;
        refs.byNameLazy = eval.config.hosts;
      } schema.service;
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
        byName.front = "igloo";
        byNameLazy.front = "igloo";
      };
      config.services.solo = {
        port = 443;
        host = "iceberg";
      };
    }
  ];

  codec = mkCodec { } schema.service;

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
    # attrsOf and lazyAttrsOf of a declaration encode the NAME at every value, alike.
    test-attrsof-ref-encodes-names = {
      expr = encoded.byName;
      expected.front = "igloo";
    };
    test-lazyattrsof-ref-encodes-names = {
      expr = encoded.byNameLazy;
      expected.front = "igloo";
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
