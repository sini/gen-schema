{
  lib,
  schemaLib,
  ...
}:
let
  inherit (schemaLib)
    mkSchemaOption
    mkInstanceRegistry
    ref
    setOf
    ;

  # --- Basic setOf test ---
  evalBasic = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption { };
        options.hosts = mkInstanceRegistry evalBasic.config.schema.host { };
        options.groups = mkInstanceRegistry evalBasic.config.schema.group {
          refs.members = evalBasic.config.hosts;
        };
        config.schema.host = {
          options.addr = lib.mkOption { type = lib.types.str; };
        };
        config.schema.group = {
          options.members = lib.mkOption {
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
  evalCoerce = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption { };
        options.hosts = mkInstanceRegistry evalCoerce.config.schema.host { };
        options.groups = mkInstanceRegistry evalCoerce.config.schema.group {
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
        config.schema.host = {
          options.addr = lib.mkOption { type = lib.types.str; };
        };
        config.schema.group = {
          options.members = lib.mkOption {
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
        config.groups.expanded = {
          members = [
            "igloo"
            { __expandAll = true; }
          ];
        };
      }
    ];
  };

  # --- nullOr (setOf (ref "kind")) ---
  evalNullable = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption { };
        options.hosts = mkInstanceRegistry evalNullable.config.schema.host { };
        options.services = mkInstanceRegistry evalNullable.config.schema.service {
          refs.hosts = evalNullable.config.hosts;
        };
        config.schema.host = {
          options.addr = lib.mkOption { type = lib.types.str; };
        };
        config.schema.service = {
          options.port = lib.mkOption { type = lib.types.int; };
          options.hosts = lib.mkOption {
            type = lib.types.nullOr (setOf (ref "host"));
            default = null;
          };
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
