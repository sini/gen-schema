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

  # --- Self-referential registry with deferred coerce ---
  # A trait's `needs` field references other traits in the same registry.
  # Custom coerce adds a tag to prove it ran; deferred = true avoids infinite recursion.
  evalSelfRef = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption { };
        options.traits = mkInstanceRegistry evalSelfRef.config.schema "trait" {
          refs.needs = {
            instances = evalSelfRef.config.traits;
            coerce = _registry: default: val: if builtins.isList default then default else [ default ];
            deferred = true;
          };
        };
        config.schema.trait = {
          options.priority = lib.mkOption {
            type = lib.types.int;
            default = 100;
          };
          options.needs = lib.mkOption {
            type = lib.types.listOf (ref "trait");
            default = [ ];
          };
        };
        config.traits.base = {
          priority = 0;
        };
        config.traits.network = {
          priority = 10;
          needs = [ "base" ];
        };
        config.traits.firewall = {
          priority = 20;
          needs = [ "network" ];
        };
      }
    ];
  };

  # --- Self-referential with custom selector coerce ---
  evalSelector = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption { };
        options.traits = mkInstanceRegistry evalSelector.config.schema "trait" {
          refs.needs = {
            instances = evalSelector.config.traits;
            coerce =
              registry: default: val:
              if builtins.isAttrs val && val ? __selectByPriority then
                let
                  threshold = val.__selectByPriority;
                in
                builtins.filter (t: t.priority <= threshold) (builtins.attrValues registry)
              else if builtins.isList default then
                default
              else
                [ default ];
            deferred = true;
          };
        };
        config.schema.trait = {
          options.priority = lib.mkOption {
            type = lib.types.int;
            default = 100;
          };
          options.needs = lib.mkOption {
            type = lib.types.listOf (ref "trait");
            default = [ ];
          };
        };
        config.traits.base = {
          priority = 0;
        };
        config.traits.network = {
          priority = 10;
        };
        config.traits.firewall = {
          priority = 20;
          needs = [ { __selectByPriority = 10; } ];
        };
      }
    ];
  };

  # --- Self-referential with setOf + deferred coerce (dedup) ---
  evalSetOf = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption { };
        options.traits = mkInstanceRegistry evalSetOf.config.schema "trait" {
          refs.deps = {
            instances = evalSetOf.config.traits;
            coerce = _registry: default: val: if builtins.isList default then default else [ default ];
            deferred = true;
          };
        };
        config.schema.trait = {
          options.deps = lib.mkOption {
            type = setOf (ref "trait");
            default = [ ];
          };
        };
        config.traits.a = { };
        config.traits.b = {
          deps = [
            "a"
            "a"
          ];
        };
      }
    ];
  };

  # --- Non-deferred coerce still works (regression guard) ---
  evalNonDeferred = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption { };
        options.hosts = mkInstanceRegistry evalNonDeferred.config.schema "host" { };
        options.services = mkInstanceRegistry evalNonDeferred.config.schema "service" {
          refs.host = {
            instances = evalNonDeferred.config.hosts;
            coerce =
              default: val:
              if builtins.isString val && val == "fallback" then evalNonDeferred.config.hosts.igloo else default;
          };
        };
        config.schema.host.options.addr = lib.mkOption { type = lib.types.str; };
        config.schema.service = {
          options.port = lib.mkOption { type = lib.types.int; };
          options.host = lib.mkOption { type = ref "host"; };
        };
        config.hosts.igloo = {
          addr = "10.0.1.1";
        };
        config.services.web = {
          port = 80;
          host = "fallback";
        };
      }
    ];
  };

  # --- Mixed deferred + non-deferred refs on same kind ---
  evalMixed = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption { };
        options.hosts = mkInstanceRegistry evalMixed.config.schema "host" { };
        options.services = mkInstanceRegistry evalMixed.config.schema "service" {
          refs.host = evalMixed.config.hosts;
          refs.depends = {
            instances = evalMixed.config.services;
            coerce = _registry: default: val: if builtins.isList default then default else [ default ];
            deferred = true;
          };
        };
        config.schema.host.options.addr = lib.mkOption { type = lib.types.str; };
        config.schema.service = {
          options.port = lib.mkOption { type = lib.types.int; };
          options.host = lib.mkOption { type = ref "host"; };
          options.depends = lib.mkOption {
            type = lib.types.listOf (ref "service");
            default = [ ];
          };
        };
        config.hosts.igloo = {
          addr = "10.0.1.1";
        };
        config.services.db = {
          port = 5432;
          host = "igloo";
        };
        config.services.api = {
          port = 8080;
          host = "igloo";
          depends = [ "db" ];
        };
      }
    ];
  };
in
{
  ref-deferred-coerce = {
    # Self-referential registry: string refs resolve to instances
    test-self-ref-resolves = {
      expr = (builtins.head evalSelfRef.config.traits.network.needs).name;
      expected = "base";
    };
    test-self-ref-chain = {
      expr = (builtins.head evalSelfRef.config.traits.firewall.needs).name;
      expected = "network";
    };
    test-self-ref-empty-default = {
      expr = evalSelfRef.config.traits.base.needs;
      expected = [ ];
    };

    # Selector-style custom coerce on self-referential registry
    test-selector-coerce-count = {
      expr = builtins.length evalSelector.config.traits.firewall.needs;
      expected = 2;
    };
    test-selector-coerce-names = {
      expr = lib.sort (a: b: a < b) (map (t: t.name) evalSelector.config.traits.firewall.needs);
      expected = [
        "base"
        "network"
      ];
    };

    # setOf with deferred coerce deduplicates
    test-setof-deferred-dedup = {
      expr = builtins.length evalSetOf.config.traits.b.deps;
      expected = 1;
    };

    # Non-deferred coerce still works (regression)
    test-non-deferred-regression = {
      expr = evalNonDeferred.config.services.web.host.addr;
      expected = "10.0.1.1";
    };

    # Mixed: non-deferred host ref resolves at option-level
    test-mixed-host-ref = {
      expr = evalMixed.config.services.api.host.addr;
      expected = "10.0.1.1";
    };
    # Mixed: deferred depends ref resolves at pipeline level
    test-mixed-deferred-depends = {
      expr = (builtins.head evalMixed.config.services.api.depends).port;
      expected = 5432;
    };
  };
}
