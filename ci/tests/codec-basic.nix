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
    schemaFn
    ;

  eval = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption {
          collections.tags = {
            default = [ ];
          };
        };
        options.hosts = mkInstanceRegistry eval.config.schema "host" { };
        config.schema.host = {
          options.addr = lib.mkOption { type = lib.types.str; };
          options.role = lib.mkOption {
            type = lib.types.str;
            default = "worker";
          };
          tags = [ "server" ];
          methods.label = schemaFn "Label" lib.types.str ({ name, addr, ... }: "${name}:${addr}");
        };
        config.hosts.igloo = {
          addr = "10.0.1.1";
          role = "web";
        };
        config.hosts.yurt = {
          addr = "10.0.1.2";
        };
      }
    ];
  };

  codec = mkCodec {
    schema = eval.config.schema;
    kind = "host";
    collections = [ "tags" ];
  };

  encoded = codec.encode eval.config.hosts.igloo;
  encodedYurt = codec.encode eval.config.hosts.yurt;
  allEncoded = codec.encodeAll eval.config.hosts;
  decoded = codec.decode {
    addr = "10.0.1.1";
    role = "web";
  };
  decodedExtra = codec.decode {
    addr = "10.0.1.1";
    role = "web";
    unknown = "dropped";
  };

  jsonStr = codec.json.serialize eval.config.hosts.igloo;
  roundTripped = codec.json.deserialize jsonStr;
  allJson = codec.json.serializeAll eval.config.hosts;
  allRoundTripped = codec.json.deserializeAll allJson;
in
{
  codec-basic = {
    test-encode-has-user-fields = {
      expr = encoded;
      expected = {
        addr = "10.0.1.1";
        role = "web";
      };
    };
    test-encode-strips-name = {
      expr = encoded ? name;
      expected = false;
    };
    test-encode-strips-id-hash = {
      expr = encoded ? id_hash;
      expected = false;
    };
    test-encode-strips-methods = {
      expr = encoded ? label;
      expected = false;
    };
    test-encode-strips-collections = {
      expr = encoded ? tags;
      expected = false;
    };
    test-encode-includes-defaults = {
      expr = encodedYurt.role;
      expected = "worker";
    };
    test-encode-all = {
      expr = builtins.attrNames allEncoded;
      expected = [
        "igloo"
        "yurt"
      ];
    };
    test-encode-all-values = {
      expr = allEncoded.igloo;
      expected = {
        addr = "10.0.1.1";
        role = "web";
      };
    };
    test-decode-passthrough = {
      expr = decoded;
      expected = {
        addr = "10.0.1.1";
        role = "web";
      };
    };
    test-decode-drops-unknown = {
      expr = decodedExtra;
      expected = {
        addr = "10.0.1.1";
        role = "web";
      };
    };
    test-json-serialize = {
      expr = builtins.fromJSON jsonStr;
      expected = {
        addr = "10.0.1.1";
        role = "web";
      };
    };
    test-json-roundtrip = {
      expr = roundTripped;
      expected = {
        addr = "10.0.1.1";
        role = "web";
      };
    };
    test-json-serialize-all = {
      expr = builtins.fromJSON allJson;
      expected = {
        igloo = {
          addr = "10.0.1.1";
          role = "web";
        };
        yurt = {
          addr = "10.0.1.2";
          role = "worker";
        };
      };
    };
    test-json-deserialize-all = {
      expr = allRoundTripped;
      expected = {
        igloo = {
          addr = "10.0.1.1";
          role = "web";
        };
        yurt = {
          addr = "10.0.1.2";
          role = "worker";
        };
      };
    };
    test-serialize-matches-json-convenience = {
      expr =
        let
          jsonFmt = {
            encode = builtins.toJSON;
            decode = builtins.fromJSON;
          };
        in
        codec.serialize jsonFmt eval.config.hosts.igloo;
      expected = jsonStr;
    };
    test-decode-missing-fields = {
      expr = codec.decode { addr = "10.0.1.1"; };
      expected = {
        addr = "10.0.1.1";
      };
    };
  };
}
