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
    declarationOf
    setOf
    ;

  basicSchema = evalSchema {
    modules = [
      {
        config.schema.host = {
          options.addr = genMerge.mkOption { type = genMerge.types.str; };
        };
        config.schema.group = {
          options.members = genMerge.mkOption {
            type = setOf (declarationOf "host");
            default = [ ];
          };
        };
      }
    ];
  };

  # --- Basic setOf test ---
  evalBasic = genMerge.evalModuleTree {
    modules = [
      {
        options.hosts = mkInstanceRegistry basicSchema.host { };
        options.groups = mkInstanceRegistry basicSchema.group {
          refs.members = evalBasic.config.hosts;
        };
        config.hosts = {
          igloo = {
            addr = "10.0.1.1";
          };
          iceberg = {
            addr = "10.0.1.2";
          };
        };
        config.groups.web = {
          members = [
            "igloo"
            "iceberg"
            "igloo"
          ];
        };
        config.groups.empty = { };
        config.groups.instances = {
          members = [
            evalBasic.config.hosts.igloo
            evalBasic.config.hosts.iceberg
            evalBasic.config.hosts.igloo
          ];
        };
      }
    ];
  };

  # --- setOf with custom coerce (expansion + dedup) ---
  evalCoerce = genMerge.evalModuleTree {
    modules = [
      {
        options.hosts = mkInstanceRegistry basicSchema.host { };
        options.groups = mkInstanceRegistry basicSchema.group {
          refs.members = {
            instances = evalCoerce.config.hosts;
            coerce =
              default: val:
              if builtins.isAttrs val && val ? __expandAll then
                builtins.attrValues evalCoerce.config.hosts
              else
                default;
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
        config.groups.expanded = {
          members = [
            "igloo"
            { __expandAll = true; }
          ];
        };
      }
    ];
  };

  nullableSchema = evalSchema {
    modules = [
      {
        config.schema.host = {
          options.addr = genMerge.mkOption { type = genMerge.types.str; };
        };
        config.schema.service = {
          options.port = genMerge.mkOption { type = genMerge.types.int; };
          options.hosts = genMerge.mkOption {
            type = genMerge.types.nullOr (setOf (declarationOf "host"));
            default = null;
          };
        };
      }
    ];
  };

  # --- nullOr (setOf (declarationOf "kind")) ---
  evalNullable = genMerge.evalModuleTree {
    modules = [
      {
        options.hosts = mkInstanceRegistry nullableSchema.host { };
        options.services = mkInstanceRegistry nullableSchema.service {
          refs.hosts = evalNullable.config.hosts;
        };
        config.hosts.igloo = {
          addr = "10.0.1.1";
        };
        config.services.web = {
          port = 80;
          hosts = [
            "igloo"
            "igloo"
          ];
        };
        config.services.none = {
          port = 443;
        };
      }
    ];
  };
in
{
  flake.tests.ref-setof = {
    test-setof-dedup = {
      expr = builtins.length evalBasic.config.groups.web.members;
      expected = 2;
    };
    test-setof-first-seen-order = {
      expr = map (h: h.name) evalBasic.config.groups.web.members;
      expected = [
        "igloo"
        "iceberg"
      ];
    };
    test-setof-empty = {
      expr = evalBasic.config.groups.empty.members;
      expected = [ ];
    };
    test-setof-instance-passthrough = {
      expr = builtins.length evalBasic.config.groups.instances.members;
      expected = 2;
    };
    test-setof-with-coerce-expansion = {
      expr = builtins.length evalCoerce.config.groups.expanded.members;
      expected = 2;
    };
    test-nullor-setof-ref-resolved = {
      expr = builtins.length evalNullable.config.services.web.hosts;
      expected = 1;
    };
    test-nullor-setof-ref-null = {
      expr = evalNullable.config.services.none.hosts;
      expected = null;
    };
  };
}
