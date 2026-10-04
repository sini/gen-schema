# THE COMPLETION STAMP (den-hoag-1a4f6) — the cells that must stay GREEN.
#
# A kind value carries `__kindSelf`, a function returning the value its schema built, so a `//` copy
# is told from the value by `==` against its own witness. The refusals, pinned by message, live in
# `ci/tests-error.nix` (`kind-value-swap-refusals`); every cell here is the control of a refused twin
# there, or an honest value whose `==` throws and must still decide `true` on every evaluator.
{
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) mkSchemaOption mkInstanceType kindEq;
  T = genMerge.types;
  intOpt = genMerge.mkOption { type = T.int; };
  tree =
    modules:
    (genMerge.evalModuleTree { } ([ { options.schema = mkSchemaOption { }; } ] ++ modules))
    .config.schema;
  k80 =
    (tree [
      {
        config.schema.host.options.port = genMerge.mkOption {
          type = T.int;
          default = 80;
        };
      }
    ]).host;
  typeOnly = _: (tree [ { config.schema.host.options.port = intOpt; } ]).host;
  via =
    type: v:
    (genMerge.evalModuleTree { } [
      { options.v = genMerge.mkOption { inherit type; }; }
      { config.v.x = v; }
    ]).config.v.x;
  # an honest kind whose computed field has no WHNF value, at the top level, inside an attrset and
  # inside a list: nix and Determinate force a shared throwing slot under `==`, Lix does not
  kindWith =
    computed:
    (genMerge.evalModuleTree { } [
      { options.schema = mkSchemaOption { inherit computed; }; }
      { config.schema.host.options.port = intOpt; }
    ]).config.schema.host;
  boomy = kindWith (_: _: { boom = throw "boom"; });
  kMeta = kindWith (
    _: _: {
      meta = {
        boom = throw "meta-boom";
        ok = 1;
      };
    }
  );
  kList = kindWith (
    _: _: {
      l = [
        (x: x)
        (throw "list-boom")
      ];
    }
  );
  foreign = (tree [ { config.schema.base.options.b = intOpt; } ]).base;
  childOf =
    parents:
    (tree [
      {
        config.schema.sub = {
          inherits = parents;
          options.extra = intOpt;
        };
      }
    ]).sub;
  aliasOf =
    parents:
    (tree [
      {
        config.schema.sub = {
          imports = parents;
          options.extra = intOpt;
        };
      }
    ]).sub;
  midOf =
    parents:
    (tree [
      {
        config.schema.mid = {
          imports = parents;
          options.m = intOpt;
        };
      }
    ]).mid;
  sameTreeChild =
    (tree [
      { config.schema.host.options.port = intOpt; }
      (
        { config, ... }:
        {
          config.schema.sub = {
            inherits = [ config.schema.host ];
            options.x = intOpt;
          };
        }
      )
    ]).sub;
  opts = k: builtins.attrNames k.options;
  instanceOf =
    kind:
    (genMerge.evalModuleTree { } [
      { options.h = genMerge.mkOption { type = mkInstanceType kind { }; }; }
      { config.h.name = "a"; }
    ]).config.h;
  # a walker of gen-demo `c94`'s `pathsNamed` shape: it descends attrsets and lists and stops at
  # anything else, so it terminates over a kind value only while the witness is a function
  leaves =
    v:
    if builtins.isAttrs v && !(v ? _type) then
      builtins.concatMap leaves (builtins.attrValues v)
    else if builtins.isList v then
      builtins.concatMap leaves v
    else
      [ 1 ];
in
{
  flake.tests.kind-value-swap = {
    test-kind-value-carries-a-function-witness-returning-itself = {
      expr = builtins.isFunction k80.__kindSelf && kindEq (k80.__kindSelf null) k80;
      expected = true;
    };
    test-kind-is-itself = {
      expr = kindEq k80 k80;
      expected = true;
    };
    test-kind-is-itself-through-anything = {
      expr = kindEq k80 (via T.anything k80) && kindEq k80 (via (T.attrsOf T.anything) k80);
      expected = true;
    };
    test-type-only-twins-are-one-kind = {
      expr = kindEq (typeOnly 1) (typeOnly 2);
      expected = true;
    };
    # a content-equal rebind is the constructed content (ADR-0034's sealed limb compares by `==`)
    test-content-equal-rebind-is-admitted = {
      expr = kindEq k80 (k80 // { }) && kindEq k80 (k80 // { inherit (k80) options; });
      expected = true;
    };
    # S8: a slot with no WHNF value is one class to the mark, on both sides
    test-throwing-slot-kind-is-itself = {
      expr = kindEq boomy boomy && kindEq boomy (via T.anything boomy);
      expected = true;
    };
    test-throwing-slot-replaced-by-another-throw-is-admitted = {
      expr = kindEq boomy (boomy // { boom = throw "other"; });
      expected = true;
    };
    # C2 (gate v0): a slot whose `==` throws on a SHARED inner thunk. The descent compares the pair
    # through slots, so nix and Determinate decide what Lix decides by identity.
    test-inner-throwing-attrset-rebound-equal-is-admitted = {
      expr = kindEq kMeta kMeta && kindEq kMeta (kMeta // { meta = kMeta.meta // { }; });
      expected = true;
    };
    test-inner-throwing-list-rebound-equal-is-admitted = {
      expr = kindEq kList kList && kindEq kList (kList // { l = kList.l ++ [ ]; });
      expected = true;
    };
    # S10
    test-a-walker-terminates-over-a-kind-value = {
      expr = builtins.length (leaves k80) > 0;
      expected = true;
    };
    # the controls of the `inherits` refusals: a value, by name and foreign, in both spellings,
    # through a diamond and through a parent
    test-same-tree-value-composes = {
      expr = opts sameTreeChild;
      expected = [
        "port"
        "x"
      ];
    };
    test-foreign-value-composes = {
      expr = map opts [
        (childOf [ foreign ])
        (aliasOf [ foreign ])
        (aliasOf [
          foreign
          foreign
        ])
      ];
      expected = [
        [
          "b"
          "extra"
        ]
        [
          "b"
          "extra"
        ]
        [
          "b"
          "extra"
        ]
      ];
    };
    test-foreign-value-through-a-parent-composes = {
      expr = opts (childOf [ (midOf [ foreign ]) ]);
      expected = [
        "b"
        "extra"
        "m"
      ];
    };
    # ★ ENUMERATED EXCEPTIONS (ADR-0025's cxlc0 rider; den-hoag-jrbis, where the `__functor`
    # self-stamp fix is evaluated). The kind's `__functor` ignores its `self`, so a `//` copy
    # reached through either door composes the ORIGINAL silently. These cells assert today's
    # admission: the closure reds them on purpose.
    test-swapped-kind-in-a-function-module-composes-unread = {
      expr = opts (aliasOf [ ({ ... }: { imports = [ (foreign // { options = { }; }) ]; }) ]);
      expected = [
        "b"
        "extra"
      ];
    };
    test-swapped-kind-under-types-submodule-composes-unread = {
      expr = builtins.attrNames (
        (genMerge.evalModuleTree { } [
          { options.h = genMerge.mkOption { type = T.submodule (foreign // { options = { }; }); }; }
          { config.h.b = 1; }
        ]).config.h
      );
      expected = [ "b" ];
    };
    test-instance-of-the-kind-value-builds = {
      expr = builtins.attrNames (instanceOf k80);
      expected = [
        "_identity"
        "_identityKeys"
        "id_hash"
        "name"
        "port"
      ];
    };
  };
}
