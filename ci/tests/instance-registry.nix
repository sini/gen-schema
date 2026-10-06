{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) evalSchema mkInstanceRegistry;

  # A bogus kind value -- no `kind`/`options` -- with an explicit description so the lazy `kind`
  # binding inside mkInstanceRegistry is never forced; only the applyPipeline guard should catch it.
  bogusRegistry = mkInstanceRegistry { description = "d"; } { no = "kind"; };

  schema = evalSchema { } [
    {
      config.schema.host = {
        options.addr = genMerge.mkOption { type = genMerge.types.str; };
        options.role = genMerge.mkOption { type = genMerge.types.str; };
      };
    }
  ];

  eval = genMerge.evalModuleTree { } [
    {
      options.hosts = mkInstanceRegistry { } schema.host;
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

    # den-hoag-cxlc0: the registry crossing is SUPPORTED. Both spellings of reading the kind off the
    # tree that declares it compose; the lazy `.default` guard must not force `kind` at the option
    # record's WHNF, which is what an eager `assert builtins.seq kind true` would do (RED there).
    test-crossing-composes-by-module-config-and-by-let-knot = {
      expr =
        let
          kindDecl = {
            options.schema = genSchema.mkSchemaOption { };
            config.schema.host.options.addr = genMerge.mkOption { type = genMerge.types.str; };
          };
          inst.config.hosts.h1.addr = "10.0.0.1";
          viaConfig =
            (genMerge.evalModuleTree { } [
              kindDecl
              ({ config, ... }: { options.hosts = mkInstanceRegistry { } config.schema.host; })
              inst
            ]).config.hosts.h1.addr;
          viaKnot =
            let
              knot = genMerge.evalModuleTree { } [
                kindDecl
                { options.hosts = mkInstanceRegistry { } knot.config.schema.host; }
                inst
              ];
            in
            knot.config.hosts.h1.addr;
        in
        [
          viaConfig
          viaKnot
        ];
      expected = [
        "10.0.0.1"
        "10.0.0.1"
      ];
    };
  };
}
