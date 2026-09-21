# THE KIND-DECLARATION KEY SPACE (den-hoag-nn4) — the cells that must stay GREEN.
#
# The refusal's own by-name cells live in `ci/tests-error.nix`, because `tryEval` discards a message
# and WHICH key was named is the whole subject. These three are the other half: every one of them is
# a key the guard must NOT refuse, and each names the reader that consumes it.
#
# ★ A guard that refuses everything passes every by-name cell in the sibling file and fails all
# three of these. That is what makes them the discriminating half rather than decoration.
{
  genSchema,
  genMerge,
  ...
}:

let
  # `mkSchemaOption`'s own construction, reached the way a caller reaches it — so what these cells
  # measure is the guard's PLACEMENT inside `mkSchemaEntryType`'s merge, not a predicate a test
  # wrapped from outside.
  kindOf =
    args: decl:
    (genMerge.evalModuleTree {
      modules = [
        { options.schema = genSchema.mkSchemaOption args; }
        { config.schema.host = decl; }
      ];
    }).config.schema.host;

  strOpt = genMerge.mkOption {
    type = genMerge.types.str;
    default = "none";
  };
in
{
  flake.tests.declaration-keys = {
    # O2 · known keys only — a declaration using nothing but the recognised vocabulary still
    # evaluates, and `parent` (a built-in collection, reader `extractedCollections`) still lands.
    test-known-keys-only-still-evaluate = {
      expr = {
        options =
          builtins.attrNames
            (kindOf { } {
              options.role = strOpt;
              parent = "env";
            }).options;
        parent =
          (kindOf { } {
            options.role = strOpt;
            parent = "env";
          }).parent;
      };
      expected = {
        options = [ "role" ];
        parent = "env";
      };
    };

    # O5 · THE FALSE-REFUSAL CONTROL. `imports` makes the def structured and `options` is absent, so
    # `extractedRefinements`' flat-style fallback reads `myPort` and its refinement contract lands on
    # the kind. A predicate reasoned from gen-merge's `configOf` alone refuses this key — `configOf`
    # never sees it — which is the false-refusal direction ADR-0008 §3 names.
    #
    # The refinement's `check` is a lambda and nix-unit compares values, so the cell asserts the
    # MESSAGES: that is the part which proves the contract arrived rather than that something did.
    test-reader-consumed-key-is-not-refused = {
      expr =
        map (r: r.message)
          (kindOf { } {
            imports = [ { } ];
            myPort = genMerge.mkOption {
              type = genSchema.refined genMerge.types.int genSchema.refinements.tcpPort;
            };
          }).refinements.myPort;
      expected = [ "must be a valid TCP port (1-65535)" ];
    };

    # O6 · THE CALLER-FUNCTION EXEMPTION. `computed` receives the RAW defs, so the key space is not
    # gen-schema's to close: `weight` is read by the caller's own function and must survive.
    test-computed-schema-is-exempt = {
      expr =
        (kindOf
          {
            computed = _collections: defs: {
              _weights = builtins.filter (x: x != null) (map (d: d.value.weight or null) defs);
            };
          }
          {
            options.role = strOpt;
            weight = 7;
          }
        )._weights;
      expected = [ 7 ];
    };

    # M2 · the published vocabulary. `_declarationKeys` is the finite, ENFORCED part of the
    # contract, derived from the same bindings the guard reads rather than restated — the reason
    # `_collectionKeys` is published (`den-hoag-4kh.53.55`: consumers hardcode what a library does
    # not publish). The prefix rule and the option-declaration rule are deliberately NOT in it.
    test-declaration-keys-are-published = {
      expr =
        (genMerge.evalModuleTree {
          modules = [ { options.s = genSchema.mkSchemaOption { }; } ];
        }).config.s._declarationKeys;
      expected = [
        "config"
        "disabledModules"
        "freeformType"
        "imports"
        "key"
        "options"
      ];
    };
  };
}
