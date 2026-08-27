{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) mkSchemaOption mkInstanceRegistry;

  # A bogus kind value -- no `kind`/`options` -- with an explicit description so the lazy `kind`
  # binding inside mkInstanceRegistry is never forced; only the applyPipeline guard should catch it.
  bogusRegistry = mkInstanceRegistry { no = "kind"; } { description = "d"; };

  eval = genMerge.evalModuleTree {
    modules = [
      {
        options.schema = mkSchemaOption { };
        options.hosts = mkInstanceRegistry eval.config.schema.host { };
        config.schema.host = {
          options.addr = genMerge.mkOption { type = genMerge.types.str; };
          options.role = genMerge.mkOption { type = genMerge.types.str; };
        };
        config.hosts.igloo = {
          addr = "10.0.1.1";
          role = "server";
        };
        config.hosts.yurt = {
          addr = "10.0.1.2";
          role = "desktop";
        };
      }
    ];
  };
in
{
  flake.tests.instance-registry = {
    test-registry-keys = {
      expr = builtins.attrNames eval.config.hosts;
      expected = [
        "igloo"
        "yurt"
      ];
    };
    test-igloo-addr = {
      expr = eval.config.hosts.igloo.addr;
      expected = "10.0.1.1";
    };
    test-yurt-role = {
      expr = eval.config.hosts.yurt.role;
      expected = "desktop";
    };
    test-names-match-keys = {
      expr = lib.mapAttrsToList (_: v: v.name) eval.config.hosts;
      expected = [
        "igloo"
        "yurt"
      ];
    };

    # den-hoag-fvxh: applyPipeline's guard. Beside the well-formed self-referential registry
    # above (test-registry-keys et al., resolved through evalModuleTree, unaffected by the fix),
    # a bogus kind value now throws as soon as the registry is actually read through the module
    # system -- the class that used to fall through to whatever refValidation/coercion produced
    # without ever checking kind-shape.
    test-control-self-referential-registry-still-resolves = {
      expr = (builtins.tryEval eval.config.hosts.igloo.addr).success;
      expected = true;
    };
    test-bogus-kind-apply-throws = {
      expr = (builtins.tryEval (bogusRegistry.apply { a = { }; })).success;
      expected = false;
    };
  };
}
