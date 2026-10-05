{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) evalSchema mkInstanceRegistry declarationOf;

  serviceSchema = evalSchema { } [
    {
      config.schema.host.options.addr = genMerge.mkOption { type = genMerge.types.str; };
      config.schema.service = {
        options.port = genMerge.mkOption { type = genMerge.types.int; };
        options.host = genMerge.mkOption { type = declarationOf "host"; };
      };
    }
  ];

  groupSchema = evalSchema { } [
    {
      config.schema.host = {
        options.addr = genMerge.mkOption { type = genMerge.types.str; };
      };
      config.schema.group = {
        options.members = genMerge.mkOption {
          type = genMerge.types.listOf (declarationOf "host");
          default = [ ];
        };
      };
    }
  ];

  # --- Simple binding (no coerce) — verifies normalizeBinding passthrough ---
  evalSimple = genMerge.evalModuleTree { } [
    {
      options.hosts = mkInstanceRegistry { } serviceSchema.host;
      options.services = mkInstanceRegistry {
        refs.host = evalSimple.config.hosts;
      } serviceSchema.service;
      config.hosts.igloo = {
        addr = "10.0.1.1";
      };
      config.services.web = {
        port = 80;
        host = "igloo";
      };
    }
  ];

  # --- Scalar coerce test ---
  evalScalar = genMerge.evalModuleTree { } [
    {
      options.hosts = mkInstanceRegistry { } serviceSchema.host;
      options.services = mkInstanceRegistry {
        refs.host = {
          instances = evalScalar.config.hosts;
          coerce =
            default: val:
            if builtins.isString val && val == "fallback" then evalScalar.config.hosts.igloo else default;
        };
      } serviceSchema.service;
      config.hosts.igloo = {
        addr = "10.0.1.1";
      };
      config.hosts.iceberg = {
        addr = "10.0.1.2";
      };
      config.services.web = {
        port = 80;
        host = "fallback";
      };
      config.services.api = {
        port = 8080;
        host = "iceberg";
      };
      config.services.direct = {
        port = 443;
        host = evalScalar.config.hosts.iceberg;
      };
    }
  ];

  # --- listOf coerce test ---
  evalList = genMerge.evalModuleTree { } [
    {
      options.hosts = mkInstanceRegistry { } groupSchema.host;
      options.groups = mkInstanceRegistry {
        refs.members = {
          instances = evalList.config.hosts;
          coerce =
            default: val:
            if builtins.isAttrs val && val ? __expandAll then
              builtins.attrValues evalList.config.hosts
            else if builtins.isList default then
              default
            else
              [ default ];
        };
      } groupSchema.group;
      config.hosts = {
        igloo = {
          addr = "10.0.1.1";
        };
        iceberg = {
          addr = "10.0.1.2";
        };
      };
      config.groups.all = {
        members = [ { __expandAll = true; } ];
      };
      config.groups.explicit = {
        members = [
          "igloo"
          "iceberg"
        ];
      };
      config.groups.mixed = {
        members = [
          "igloo"
          evalList.config.hosts.iceberg
        ];
      };
    }
  ];
in
{
  flake.tests.ref-custom-coerce = {
    test-scalar-coerce-custom = {
      expr = evalScalar.config.services.web.host.addr;
      expected = "10.0.1.1";
    };
    test-scalar-coerce-delegates-default = {
      expr = evalScalar.config.services.api.host.addr;
      expected = "10.0.1.2";
    };
    test-scalar-coerce-instance-passthrough = {
      expr = evalScalar.config.services.direct.host.addr;
      expected = "10.0.1.2";
    };
    test-simple-binding-unchanged = {
      expr = evalSimple.config.services.web.host.addr;
      expected = "10.0.1.1";
    };
    test-listof-coerce-default = {
      expr = map (h: h.addr) evalList.config.groups.explicit.members;
      expected = [
        "10.0.1.1"
        "10.0.1.2"
      ];
    };
    test-listof-coerce-mixed = {
      expr = map (h: h.addr) evalList.config.groups.mixed.members;
      expected = [
        "10.0.1.1"
        "10.0.1.2"
      ];
    };
    test-listof-coerce-expansion = {
      expr = builtins.length evalList.config.groups.all.members;
      expected = 2;
    };
    test-scalar-coerce-expansion-error = {
      expr =
        let
          thingSchema = evalSchema { } [
            {
              config.schema.host.options.addr = genMerge.mkOption { type = genMerge.types.str; };
              config.schema.thing.options.host = genMerge.mkOption { type = declarationOf "host"; };
            }
          ];
          evalBad = genMerge.evalModuleTree { } [
            {
              options.hosts = mkInstanceRegistry { } thingSchema.host;
              options.things = mkInstanceRegistry {
                refs.host = {
                  instances = evalBad.config.hosts;
                  coerce = _default: _val: [
                    evalBad.config.hosts.igloo
                    evalBad.config.hosts.igloo
                  ];
                };
              } thingSchema.thing;
              config.hosts.igloo = {
                addr = "10.0.1.1";
              };
              config.things.bad = {
                host = "igloo";
              };
            }
          ];
        in
        builtins.tryEval (builtins.seq evalBad.config.things.bad.host null);
      expected = {
        success = false;
        value = false;
      };
    };
  };
}
