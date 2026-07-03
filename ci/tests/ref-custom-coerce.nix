{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) mkSchemaOption mkInstanceRegistry ref;

  # --- Simple binding (no coerce) — verifies normalizeBinding passthrough ---
  evalSimple = genMerge.evalModuleTree {
    modules = [
      {
        options.schema = mkSchemaOption { };
        options.hosts = mkInstanceRegistry evalSimple.config.schema.host { };
        options.services = mkInstanceRegistry evalSimple.config.schema.service {
          refs.host = evalSimple.config.hosts;
        };
        config.schema.host.options.addr = genMerge.mkOption { type = genMerge.types.str; };
        config.schema.service = {
          options.port = genMerge.mkOption { type = genMerge.types.int; };
          options.host = genMerge.mkOption { type = ref "host"; };
        };
        config.hosts.igloo = {
          addr = "10.0.1.1";
        };
        config.services.web = {
          port = 80;
          host = "igloo";
        };
      }
    ];
  };

  # --- Scalar coerce test ---
  evalScalar = genMerge.evalModuleTree {
    modules = [
      {
        options.schema = mkSchemaOption { };
        options.hosts = mkInstanceRegistry evalScalar.config.schema.host { };
        options.services = mkInstanceRegistry evalScalar.config.schema.service {
          refs.host = {
            instances = evalScalar.config.hosts;
            coerce =
              default: val:
              if builtins.isString val && val == "fallback" then evalScalar.config.hosts.igloo else default;
          };
        };
        config.schema.host = {
          options.addr = genMerge.mkOption { type = genMerge.types.str; };
        };
        config.schema.service = {
          options.port = genMerge.mkOption { type = genMerge.types.int; };
          options.host = genMerge.mkOption { type = ref "host"; };
        };
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
  };

  # --- listOf coerce test ---
  evalList = genMerge.evalModuleTree {
    modules = [
      {
        options.schema = mkSchemaOption { };
        options.hosts = mkInstanceRegistry evalList.config.schema.host { };
        options.groups = mkInstanceRegistry evalList.config.schema.group {
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
        };
        config.schema.host = {
          options.addr = genMerge.mkOption { type = genMerge.types.str; };
        };
        config.schema.group = {
          options.members = genMerge.mkOption {
            type = genMerge.types.listOf (ref "host");
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
  };
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
          evalBad = genMerge.evalModuleTree {
            modules = [
              {
                options.schema = mkSchemaOption { };
                options.hosts = mkInstanceRegistry evalBad.config.schema.host { };
                options.things = mkInstanceRegistry evalBad.config.schema.thing {
                  refs.host = {
                    instances = evalBad.config.hosts;
                    coerce = _default: _val: [
                      evalBad.config.hosts.igloo
                      evalBad.config.hosts.igloo
                    ];
                  };
                };
                config.schema.host.options.addr = genMerge.mkOption { type = genMerge.types.str; };
                config.schema.thing.options.host = genMerge.mkOption { type = ref "host"; };
                config.hosts.igloo = {
                  addr = "10.0.1.1";
                };
                config.things.bad = {
                  host = "igloo";
                };
              }
            ];
          };
        in
        builtins.tryEval (builtins.seq evalBad.config.things.bad.host null);
      expected = {
        success = false;
        value = false;
      };
    };
  };
}
