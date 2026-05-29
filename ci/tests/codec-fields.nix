{
  lib,
  genSchema,
  ...
}:
let
  inherit (genSchema)
    mkSchemaOption
    mkInstanceRegistry
    mkCodec
    ref
    ;

  eval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption { };
        options.peers = mkInstanceRegistry eval.config.schema.peer { };
        options.hosts = mkInstanceRegistry eval.config.schema.host {
          refs.peer = eval.config.peers;
        };
        config.schema.peer = {
          options.addr = lib.mkOption { type = lib.types.str; };
        };
        config.schema.host = {
          options.addr = lib.mkOption { type = lib.types.str; };
          options.role = lib.mkOption { type = lib.types.str; };
          options.secret = lib.mkOption {
            type = lib.types.str;
            default = "s3cret";
          };
          options.peer = lib.mkOption {
            type = lib.types.nullOr (ref "peer");
            default = null;
          };
          options.meta = lib.mkOption {
            type = lib.types.submodule {
              options.region = lib.mkOption {
                type = lib.types.str;
                default = "us-east";
              };
              options.zone = lib.mkOption {
                type = lib.types.str;
                default = "a";
              };
              options.internal = lib.mkOption {
                type = lib.types.str;
                default = "x";
              };
            };
            default = { };
          };
        };
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
  };

  igloo = eval.config.hosts.igloo;

  # Codec with exclusion
  codecExclude = mkCodec eval.config.schema.host {
    fields = {
      secret = {
        exclude = true;
      };
    };
  };

  # Codec with custom encode/decode
  codecCustom = mkCodec eval.config.schema.host {
    fields = {
      secret = {
        exclude = true;
      };
      addr = {
        encode = v: "ip:${v}";
        decode = v: lib.removePrefix "ip:" v;
      };
    };
  };

  # Codec with recursive fields
  codecNested = mkCodec eval.config.schema.host {
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
  };

  # Codec with custom encoder suppressing ref auto-encode
  codecCustomRef = mkCodec eval.config.schema.host {
    fields = {
      secret = {
        exclude = true;
      };
      peer = {
        encode = v: if v == null then "none" else "peer:${v.name}";
        decode = v: if v == "none" then null else lib.removePrefix "peer:" v;
      };
    };
  };
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
          c = mkCodec eval.config.schema.host {
            fields = {
              nonexistent = {
                exclude = true;
              };
            };
          };
        in
        (c.encode igloo).addr;
      expected = "10.0.1.1";
    };
    test-encode-nonexistent-throws = {
      expr = builtins.tryEval (
        mkCodec eval.config.schema.host {
          fields = {
            nonexistent = {
              encode = v: v;
            };
          };
        }
      );
      expected = {
        success = false;
        value = false;
      };
    };
  };
}
