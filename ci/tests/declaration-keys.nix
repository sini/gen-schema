# THE KIND-DECLARATION KEY SPACE (den-hoag-nn4) — the cells that must stay GREEN.
#
# The refusal's own by-name cells live in `ci/tests-error.nix`, because `tryEval` discards a message
# and WHICH key was named is the whole subject. These two are the other half: each is a key the guard
# must NOT refuse, and each names the reader that consumes it. The false-refusal control for an
# option key — one the option plane reads — is the `reverse-half-read` group in `auto-integration.nix`.
#
# ★ A guard that refuses everything passes every by-name cell in the sibling file and fails
# both of these. That is what makes them the discriminating half rather than decoration.
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
    (genMerge.evalModuleTree { } [
      { options.schema = genSchema.mkSchemaOption args; }
      { config.schema.host = decl; }
    ]).config.schema.host;

  strOpt = genMerge.mkOption {
    type = genMerge.types.str;
    default = "none";
  };

  # G1–G4 (den-hoag-1n12c §3a) · each a BARE key on a SHORTHAND kind decl, read the way a caller
  # actually reads it — through an instance, not off the kind record. A kind's `foo` is DATA to
  # `configOf`, never a field the kind value itself exposes (the same "discarded unread, invisible
  # to every instrument" reasoning as an unrecognised key — the only difference is nothing refuses
  # it), so `foo` needs an imported OPTION to land somewhere observable, and an INSTANCE to read the
  # option's resolved value off. Matches `reports/den-hoag-1n12c-rows.nix`, the fixtures the spec's
  # own gating oracle (3a) was evaluated against, verbatim.
  int0 = genMerge.mkOption {
    type = genMerge.types.int;
    default = 0;
  };
  fooOpt = {
    options.foo = int0;
  };
  instanceOf =
    args: decl:
    let
      schema = genSchema.evalSchema { schemaOption = genSchema.mkSchemaOption args; } [
        { config.schema.k = decl; }
      ];
    in
    (genMerge.evalModuleTree { } [
      { options.ks = genSchema.mkInstanceRegistry { } schema.k; }
      { config.ks.a = { }; }
    ]).config.ks.a;
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
    #
    # den-hoag-1n12c: the expected side is DERIVED from gen-merge's own published
    # `moduleSyntax.structured`, never a literal copy of it — a literal here is itself the
    # restatement s7826 showed drifts. This cell now discriminates gen-schema's derivation
    # against gen-merge's, not against a frozen guess of what gen-merge once enforced.
    test-declaration-keys-are-published = {
      expr =
        (genMerge.evalModuleTree { } [ { options.s = genSchema.mkSchemaOption { }; } ])
        .config.s._declarationKeys;
      expected = builtins.sort (a: b: a < b) genMerge.moduleSyntax.structured;
    };

    # G1 · a bare key beside `imports` alone is config: `imports`-only no longer structures the decl
    # (`moduleSyntax.structuring` narrowed to `config`/`options`), so `foo = 1` is a shorthand
    # definition for the option `imports` brought in, not an unrecognised declaration key.
    test-bare-key-beside-imports-is-config = {
      expr =
        (instanceOf { } {
          imports = [ fooOpt ];
          foo = 1;
        }).foo;
      expected = 1;
    };

    # G2 · the same key beside `imports` AND `freeformType` — neither structures the decl either,
    # together or alone.
    test-bare-key-beside-freeformType-is-config = {
      expr =
        (instanceOf { } {
          imports = [ fooOpt ];
          freeformType = genMerge.types.attrsOf genMerge.types.int;
          foo = 1;
        }).foo;
      expected = 1;
    };

    # G3 · `meta` beside a genuine `config` key is FOLDED, not refused: `declarationKeys` is now
    # `moduleSyntax.structured` in full (11 names, `meta` among them) rather than gen-schema's old
    # 6-name copy, which never included it.
    test-meta-beside-config-is-folded = {
      expr =
        (instanceOf { } {
          imports = [
            fooOpt
            { options.meta.m = int0; }
          ];
          config.foo = 1;
          meta.m = 7;
        }).meta.m;
      expected = 7;
    };

    # G4 · `require` is gen-merge's own shorthand-module vocabulary (it joins `imports` on a
    # SHORTHAND decl, `moduleSyntax.shorthandMeta`), not an arbitrary collection name gen-schema
    # must recognise by a hand copy — a second `imports`-shaped path to the same option lands the
    # same config.
    test-require-on-a-shorthand-kind-imports = {
      expr =
        (instanceOf { } {
          imports = [ fooOpt ];
          require = [ { foo = 1; } ];
        }).foo;
      expected = 1;
    };
  };
}
