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
    ;

  schema = evalSchema { } [
    {
      config.schema.peer = {
        options.addr = genMerge.mkOption { type = genMerge.types.str; };
      };
      config.schema.host = {
        options.addr = genMerge.mkOption { type = genMerge.types.str; };
        options.role = genMerge.mkOption { type = genMerge.types.str; };
        options.secret = genMerge.mkOption {
          type = genMerge.types.str;
          default = "s3cret";
        };
        options.peer = genMerge.mkOption {
          type = genMerge.types.nullOr (declarationOf "peer");
          default = null;
        };
        options.meta = genMerge.mkOption {
          type = genMerge.types.submodule {
            options.region = genMerge.mkOption {
              type = genMerge.types.str;
              default = "us-east";
            };
            options.zone = genMerge.mkOption {
              type = genMerge.types.str;
              default = "a";
            };
            options.internal = genMerge.mkOption {
              type = genMerge.types.str;
              default = "x";
            };
          };
          default = { };
        };
      };
    }
  ];

  eval = genMerge.evalModuleTree { } [
    {
      options.peers = mkInstanceRegistry { } schema.peer;
      options.hosts = mkInstanceRegistry {
        refs.peer = eval.config.peers;
      } schema.host;
      config.peers = {
        yurt = {
          addr = "10.0.1.2";
        };
      };
      config.hosts.igloo = {
        addr = "10.0.1.1";
        role = "web";
        peer = "yurt";
        meta.region = "eu-west";
      };
      config.hosts.yurt = {
        addr = "10.0.1.2";
        role = "worker";
      };
    }
  ];

  igloo = eval.config.hosts.igloo;

  # Codec with exclusion
  codecExclude = mkCodec {
    fields = {
      secret = {
        exclude = true;
      };
    };
  } schema.host;

  # Codec with custom encode/decode
  codecCustom = mkCodec {
    fields = {
      secret = {
        exclude = true;
      };
      addr = {
        encode = v: "ip:${v}";
        decode = v: lib.removePrefix "ip:" v;
      };
    };
  } schema.host;

  # Codec with recursive fields
  codecNested = mkCodec {
    fields = {
      secret = {
        exclude = true;
      };
      meta = {
        fields = {
          region = { };
          zone = { };
          internal = {
            exclude = true;
          };
        };
      };
    };
  } schema.host;

  # Codec with custom encoder suppressing ref auto-encode
  codecCustomRef = mkCodec {
    fields = {
      secret = {
        exclude = true;
      };
      peer = {
        encode = v: if v == null then "none" else "peer:${v.name}";
        decode = v: if v == "none" then null else lib.removePrefix "peer:" v;
      };
    };
  } schema.host;
in
{
  flake.tests.codec-fields = {
    test-exclude-removes-field = {
      expr = (codecExclude.encode igloo) ? secret;
      expected = false;
    };
    test-exclude-keeps-others = {
      expr = (codecExclude.encode igloo).addr;
      expected = "10.0.1.1";
    };
    test-custom-encode = {
      expr = (codecCustom.encode igloo).addr;
      expected = "ip:10.0.1.1";
    };
    test-custom-decode = {
      expr =
        (codecCustom.decode {
          addr = "ip:10.0.1.1";
          role = "web";
        }).addr;
      expected = "10.0.1.1";
    };
    test-nested-fields-filter = {
      expr = (codecNested.encode igloo).meta;
      expected = {
        region = "eu-west";
        zone = "a";
      };
    };
    test-nested-decode = {
      expr =
        (codecNested.decode {
          addr = "10.0.1.1";
          role = "web";
          meta = {
            region = "eu-west";
            zone = "a";
          };
        }).meta;
      expected = {
        region = "eu-west";
        zone = "a";
      };
    };
    test-custom-ref-encode = {
      expr = (codecCustomRef.encode igloo).peer;
      expected = "peer:yurt";
    };
    test-custom-ref-decode = {
      expr =
        (codecCustomRef.decode {
          addr = "10.0.1.1";
          role = "web";
          peer = "peer:yurt";
        }).peer;
      expected = "yurt";
    };
    test-custom-ref-null = {
      expr = (codecCustomRef.encode eval.config.hosts.yurt).peer;
      expected = "none";
    };
    test-exclude-nonexistent-silent = {
      expr =
        let
          c = mkCodec {
            fields = {
              nonexistent = {
                exclude = true;
              };
            };
          } schema.host;
        in
        (c.encode igloo).addr;
      expected = "10.0.1.1";
    };
    test-encode-nonexistent-throws = {
      expr = builtins.tryEval (
        mkCodec {
          fields = {
            nonexistent = {
              encode = v: v;
            };
          };
        } schema.host
      );
      expected = {
        success = false;
        value = false;
      };
    };
  };
}
