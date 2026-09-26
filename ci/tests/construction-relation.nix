# den-hoag-bfc0k: a type gen-schema builds per construction merges with a second one exactly when the
# two are one construction (lib/default.nix `constructionRelation`), and every other same-named pair
# is refused. Before it, every pair merged on the NAME and the later declaration decided: two entry
# types differing in `strict` published whichever came last, and a collection only the first one
# declared was dropped, with nothing said.
#
# Each cell answers MERGED or REFUSED under tryEval, so the relation is what is pinned and not a
# message; the controls merge, so a relation that refuses everything reds them.
{
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema)
    mkSchemaEntryType
    mkSchemaOption
    mkStrictModule
    declarationOf
    setOf
    ;
  t = genMerge.types;
  verdict =
    v:
    let
      r = builtins.tryEval (builtins.deepSeq v true);
    in
    if r.success then "MERGED" else "REFUSED";
  cfg = mods: (genMerge.evalModuleTree { modules = mods; }).config;
  fn = _: _: { };
  fn2 = _: _: { };

  # two declarations of one option, typed by `a` and `b`
  entry =
    a: b:
    verdict
      (cfg [
        { options.kinds = genMerge.mkOption { type = t.lazyAttrsOf a; }; }
        { options.kinds = genMerge.mkOption { type = t.lazyAttrsOf b; }; }
        { kinds.k = { }; }
      ]).kinds.k.strict;
  schemaKinds =
    mods: verdict (builtins.attrNames (cfg (mods ++ [ { config.schema.k = { }; } ])).schema.k);
  x =
    a: b: val:
    verdict
      (cfg [
        { options.x = genMerge.mkOption { type = a; }; }
        { options.x = genMerge.mkOption { type = b; }; }
        { x = val; }
      ]).x;
  inst =
    mods: val:
    verdict
      (cfg [
        {
          options.inst = genMerge.mkOption {
            type = t.submodule {
              imports = mods ++ [ { options.a = genMerge.mkOption { type = t.int; }; } ];
            };
          };
        }
        { inst = val; }
      ]).inst.a;
in
{
  flake.tests.construction-relation = {
    # ── schemaKindEntry, per call ──
    test-entry-one-construction-merges = {
      expr = {
        twoCalls = entry (mkSchemaEntryType { }) (mkSchemaEntryType { });
        equalCollections =
          entry (mkSchemaEntryType { collections.tags.default = [ ]; })
            (mkSchemaEntryType {
              collections.tags.default = [ ];
            });
        sharedFunction = entry (mkSchemaEntryType { computed = fn; }) (mkSchemaEntryType {
          computed = fn;
        });
      };
      expected = {
        twoCalls = "MERGED";
        equalCollections = "MERGED";
        sharedFunction = "MERGED";
      };
    };

    test-entry-two-constructions-refuse = {
      expr = {
        strictTF = entry (mkSchemaEntryType { strict = true; }) (mkSchemaEntryType {
          strict = false;
        });
        strictFT = entry (mkSchemaEntryType { strict = false; }) (mkSchemaEntryType {
          strict = true;
        });
        collections = entry (mkSchemaEntryType { collections.tags.default = [ ]; }) (mkSchemaEntryType { });
        distinctFunctions = entry (mkSchemaEntryType { computed = fn; }) (mkSchemaEntryType {
          computed = fn2;
        });
      };
      expected = {
        strictTF = "REFUSED";
        strictFT = "REFUSED";
        collections = "REFUSED";
        distinctFunctions = "REFUSED";
      };
    };

    # ── schemaKindEntry, per `mkSchemaOption` call: its `schema` type carries the entry's relation ──
    test-schema-option-redeclared-reads-its-kinds = {
      expr =
        let
          o = mkSchemaOption { mkType = { kind, ... }: { inherit kind; }; };
        in
        {
          oneValue = schemaKinds [
            { options.schema = o; }
            { options.schema = o; }
          ];
          twoCalls = schemaKinds [
            { options.schema = mkSchemaOption { }; }
            { options.schema = mkSchemaOption { }; }
          ];
          differing = schemaKinds [
            { options.schema = mkSchemaOption { strict = true; }; }
            { options.schema = mkSchemaOption { strict = false; }; }
          ];
        };
      expected = {
        oneValue = "MERGED";
        twoCalls = "MERGED";
        differing = "REFUSED";
      };
    };

    # ── ref(<kind>) and the setOf over it ──
    test-ref-kind-is-its-construction = {
      expr = {
        twoCalls = x (declarationOf "host") (declarationOf "host") "a";
        setOfTwoCalls = x (setOf (declarationOf "host")) (setOf (declarationOf "host")) [ ];
        differing = x (declarationOf "host") (declarationOf "user") "a";
      };
      expected = {
        twoCalls = "MERGED";
        setOfTwoCalls = "MERGED";
        differing = "REFUSED";
      };
    };

    # ── strict, per evaluation of mkStrictModule ──
    test-strict-module-imported-twice = {
      expr = {
        oneKind = inst [ (mkStrictModule "k") (mkStrictModule "k") ] { a = 1; };
        twoKinds = inst [ (mkStrictModule "k") (mkStrictModule "j") ] { a = 1; };
      };
      expected = {
        oneKind = "MERGED";
        twoKinds = "REFUSED";
      };
    };
    # ── a type record inside a compared component (den-hoag-bfc0k) ──
    # A facet's `option.type` is the one position the `keySemantics` grammar places a type record,
    # and an exported record is cyclic. Its back-edge sits under `description`, which the evaluator
    # interns at startup, so a bare `==` between two constructions reaches it before any closure and
    # aborts; `constructionRelation` compares through `closuresFirst` and refuses. The shared facet
    # and one type written in two facets are one construction each and merge.
    test-a-facet-type-record-is-compared-closures-first = {
      expr =
        let
          knot =
            _:
            let
              r = {
                loop = r;
              };
            in
            genMerge.types.mkOptionType {
              name = "shed";
              description = r;
              check = builtins.isString;
            };
          facet = ty: {
            shed = {
              category = "facet";
              option = genMerge.mkOption { type = ty; };
            };
          };
          one = knot 0;
          shared = facet one;
        in
        {
          twoConstructions = entry (mkSchemaEntryType { keySemantics = facet (knot 1); }) (mkSchemaEntryType {
            keySemantics = facet (knot 2);
          });
          sharedFacet = entry (mkSchemaEntryType { keySemantics = shared; }) (mkSchemaEntryType {
            keySemantics = shared;
          });
          oneTypeTwoFacets = entry (mkSchemaEntryType { keySemantics = facet one; }) (mkSchemaEntryType {
            keySemantics = facet one;
          });
        };
      expected = {
        twoConstructions = "REFUSED";
        sharedFacet = "MERGED";
        oneTypeTwoFacets = "MERGED";
      };
    };

    # ── a facet typed by a non-record (den-hoag-6b5ia) ──
    # `type = "gauge"` is the NixOS spelling, and `keySemanticsRecords` hands it to `closuresFirst` as
    # a record. gen-merge's `closuresOf` ran `intersectAttrs` over it, an evaluator type error that
    # `tryEval` does not catch, so both rows aborted the suite (☢️); a non-record now contributes no
    # closures and the value decides.
    test-a-facet-typed-by-a-string-answers = {
      expr =
        let
          facet = ty: {
            gauge = {
              category = "facet";
              option = genMerge.mkOption { type = ty; };
            };
          };
        in
        {
          oneString = entry (mkSchemaEntryType { keySemantics = facet "gauge"; }) (mkSchemaEntryType {
            keySemantics = facet "gauge";
          });
          twoStrings = entry (mkSchemaEntryType { keySemantics = facet "gauge"; }) (mkSchemaEntryType {
            keySemantics = facet "meter";
          });
        };
      expected = {
        oneString = "MERGED";
        twoStrings = "REFUSED";
      };
    };
  };
}
