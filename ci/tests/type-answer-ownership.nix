# A type gen-schema DERIVES from a gen-merge one must own the protocol answers that describe it.
#
# THE CLASS. `mkOptionType` completes a type by stamping the nixpkgs protocol onto the record it
# is handed, and the functor it mints points back at THAT record. So `completed // { … }` builds a
# type whose every unnamed field still answers for the LEFT operand — and two of those fields
# rebuild it: `functor.type`, which is what `typeMerge` returns when an option is declared twice,
# and `substSubModules`. A derived type that travels through either comes back as the base, with
# whatever discriminator the derivation added silently gone. The construction skips the completion
# path entirely, so no refusal a completed type would face applies to it.
#
# Each cell below puts one derived type through the operation that used to lose its answer.
# test-control-* seeds the class inline and shows the loss still happening, so a cell that passes
# because the predicate cannot fail is distinguishable from a cell that passes because the fix holds.
{
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema)
    mkSchemaEntryType
    ref
    setOf
    ;

  refHost = ref "host";
  setType = setOf refHost;
  entryType = mkSchemaEntryType { };
  tcpPort = genSchema.refinements.tcpPort;
  refinedPort = genSchema.refined genMerge.types.int [ tcpPort ];

  # A redeclaration of the same option: nixpkgs combines the two declarations by asking one type
  # to merge the other's functor.
  redeclare = t: t.typeMerge t.functor;

  # The seeded class member — setOf as it was built before, an override over a completed listOf.
  controlSetOf =
    let
      listType = genMerge.types.listOf refHost;
    in
    listType
    // {
      name = "setOf(${refHost.name})";
      isSetOf = true;
      nestedTypes = {
        elemType = refHost;
      };
    };

  # A schema kind entry's merge extracts declared collections onto the result; deferredModule's
  # merge only wraps the defs as `{ imports = [ … ]; }`. Which one a type carries is the
  # behavioural discriminator, so ask it rather than comparing functions.
  extractsCollections =
    t:
    (t.merge
      [ "host" ]
      [
        {
          file = "<test>";
          value = {
            methods.greet = _: "hi";
          };
        }
      ]
    ) ? methods;
in
{
  flake.tests.type-answer-ownership = {
    # ── setOf ──────────────────────────────────────────────────────────────────────────────────
    # Rebuilding over a replacement module set used to hand back listOf's answer: null before
    # gen-merge gave listOf a rebuilding substSubModules, a type named "listOf" after it.
    test-setof-substsubmodules-rebuilds-a-setof = {
      expr =
        let
          r = setType.substSubModules [ { } ];
        in
        {
          name = r.name;
          isSetOf = r.isSetOf or false;
          elem = r.nestedTypes.elemType.refKind or null;
        };
      expected = {
        name = "setOf(ref(host))";
        isSetOf = true;
        elem = "host";
      };
    };

    test-setof-survives-redeclaration = {
      expr =
        let
          r = redeclare setType;
        in
        {
          name = r.name;
          isSetOf = r.isSetOf or false;
        };
      expected = {
        name = "setOf(ref(host))";
        isSetOf = true;
      };
    };

    # setOf and listOf are different types, so a declaration of each is a conflict, not a merge.
    test-setof-does-not-merge-with-plain-listof = {
      expr = setType.typeMerge (genMerge.types.listOf refHost).functor;
      expected = null;
    };

    # ── ref ────────────────────────────────────────────────────────────────────────────────────
    # refKind is what mkInstanceRegistry detects to inject resolution; a rebuilt ref without it is
    # a ref nothing will ever bind.
    test-ref-survives-redeclaration = {
      expr = (redeclare refHost).refKind or null;
      expected = "host";
    };

    # ── schema kind entry ──────────────────────────────────────────────────────────────────────
    test-entry-is-not-named-for-the-type-it-delegates-to = {
      expr = entryType.name;
      expected = "schemaKindEntry";
    };

    test-entry-survives-redeclaration = {
      expr =
        let
          r = redeclare entryType;
        in
        {
          name = r.name;
          collections = extractsCollections r;
        };
      expected = {
        name = "schemaKindEntry";
        collections = true;
      };
    };

    # ── refined ────────────────────────────────────────────────────────────────────────────────
    # __schema carries the predicates; a redeclaration that came back as the bare base would leave
    # the option typed but unrefined, with nothing to report that the contract had gone.
    test-refined-survives-redeclaration = {
      expr =
        let
          r = refinedPort.typeMerge (genSchema.refined genMerge.types.int [ tcpPort ]).functor;
        in
        {
          refinements = builtins.length r.__schema.refinements;
          base = r.__schema.baseType.name;
        };
      expected = {
        refinements = 1;
        base = "int";
      };
    };

    # The two axes kept apart: the type still speaks the base's value vocabulary in its error
    # messages, while the functor carries the identity a redeclaration is compared on.
    test-refined-names-the-base-and-the-functor-distinguishes = {
      expr = {
        name = refinedPort.name;
        functor = refinedPort.functor.name;
      };
      expected = {
        name = "int";
        functor = "refined<int>";
      };
    };

    # Fail CLOSED, both directions: declaring an option once as refined and once as the bare base
    # is a conflict to state, not a refinement to drop.
    test-refined-does-not-merge-with-its-bare-base = {
      expr = {
        refinedFirst = refinedPort.typeMerge genMerge.types.int.functor;
        bareFirst = genMerge.types.int.typeMerge refinedPort.functor;
      };
      expected = {
        refinedFirst = null;
        bareFirst = null;
      };
    };

    # ── controls ───────────────────────────────────────────────────────────────────────────────
    # The class, seeded here and still firing: an override over a completed listOf answers as a
    # listOf, and the isSetOf discriminator the override added does not survive the rebuild. If
    # this ever reports a setOf, the predicate above has stopped being able to fail.
    test-control-override-over-completed-type-loses-its-answer = {
      expr =
        let
          r = redeclare controlSetOf;
        in
        {
          name = r.name;
          isSetOf = r.isSetOf or false;
        };
      expected = {
        name = "listOf";
        isSetOf = false;
      };
    };

    # The other half of the same control: the operation is reached at all, and the two types are
    # answer-distinguishable. A fixed setOf and the seeded one disagree about their own name.
    test-control-fixed-and-seeded-setof-disagree = {
      expr = (redeclare setType).name == (redeclare controlSetOf).name;
      expected = false;
    };
  };
}
