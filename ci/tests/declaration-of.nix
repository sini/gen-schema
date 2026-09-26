# `declarationOf` — the type of a field holding a declaration (den-hoag-2zjg1). One fixture, both
# modes: a deferred field bound through `refs`, written once by identifier (a reference) and once by
# declaration value (a registry instance), a `setOf` over the same kind with a duplicate, and the
# direct mode over a registry. Both written forms resolve to the instance.
#
# The old name `ref` is a tombstone: reaching it and applying it are both refused, catchably. WHICH
# refusal fired is pinned in ../tests-error.nix (`declaration-of-refusals`) and at the root seam by
# the harness-generated `root-surface-retired.test-retired-ref`.
{
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

  schema = evalSchema {
    modules = [
      {
        config.schema.host.options.addr = genMerge.mkOption { type = genMerge.types.str; };
        config.schema.service.options.host = genMerge.mkOption { type = declarationOf "host"; };
        config.schema.service.options.peers = genMerge.mkOption { type = setOf (declarationOf "host"); };
      }
    ];
  };

  eval = genMerge.evalModuleTree {
    modules = [
      {
        options.hosts = mkInstanceRegistry schema.host { };
        options.services = mkInstanceRegistry schema.service {
          refs = {
            host = eval.config.hosts;
            peers = eval.config.hosts;
          };
        };
        config.hosts.igloo.addr = "10.0.1.1";
        config.hosts.yurt.addr = "10.0.1.2";
        config.services.byName = {
          host = "igloo";
          peers = [
            "igloo"
            "yurt"
            "igloo"
          ];
        };
        config.services.byValue = {
          host = eval.config.hosts.yurt;
          peers = [ eval.config.hosts.yurt ];
        };
      }
    ];
  };

  direct = genMerge.evalModuleTree {
    modules = [
      {
        options.hosts = mkInstanceRegistry schema.host { };
        options.pick = genMerge.mkOption { type = declarationOf direct.config.hosts; };
        config.hosts.igloo.addr = "10.0.1.1";
        config.pick = "igloo";
      }
    ];
  };

  svc = eval.config.services;
  refused = v: (builtins.tryEval (builtins.seq v true)).success;
in
{
  flake.tests.declaration-of = {
    test-deferred-by-identifier-resolves = {
      expr = svc.byName.host.addr;
      expected = "10.0.1.1";
    };
    test-deferred-by-declaration-resolves = {
      expr = svc.byValue.host.addr;
      expected = "10.0.1.2";
    };
    test-both-forms-resolve-to-the-registry-instance = {
      expr = [
        (svc.byName.host.id_hash == eval.config.hosts.igloo.id_hash)
        (svc.byValue.host.id_hash == eval.config.hosts.yurt.id_hash)
      ];
      expected = [
        true
        true
      ];
    };
    test-set-dedups-first-seen = {
      expr = map (h: h.name) svc.byName.peers;
      expected = [
        "igloo"
        "yurt"
      ];
    };
    test-direct-mode-resolves = {
      expr = direct.config.pick.addr;
      expected = "10.0.1.1";
    };
    test-type-names = {
      expr = {
        deferred = (declarationOf "host").name;
        set = (setOf (declarationOf "host")).name;
        direct = (declarationOf direct.config.hosts).name;
      };
      expected = {
        deferred = "declarationOf(host)";
        set = "setOf(declarationOf(host))";
        direct = "declarationOf";
      };
    };
    # The tombstone refuses on access and on application, and an argument that cannot be coerced to
    # a string still meets a catchable refusal (the message interpolates nothing). The live control
    # beside them is the new name answering in the same shape.
    test-old-name-refused-catchably = {
      expr = {
        access = refused genSchema.ref;
        apply = refused (genSchema.ref "host");
        lambdaArg = refused (genSchema.ref (x: x));
        control = refused (declarationOf "host");
      };
      expected = {
        access = false;
        apply = false;
        lambdaArg = false;
        control = true;
      };
    };
  };
}
