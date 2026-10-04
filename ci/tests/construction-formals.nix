# A NAME WITH A KIND-LEVEL READING WRITTEN AT A KIND ENTRY'S TOP LEVEL (den-hoag-q17cc) — the cells
# that must stay GREEN, and the population pin.
#
# The by-name refusals live in `ci/tests-error.nix` (`construction-formal-refusals`), because `tryEval`
# discards the message. These are the other half: the population refuses on both branches, the routes
# that are NOT the misreading still write, the imports route refuses, and a custom `mkType` that
# builds its own modules is pinned as the boundary. A door that refused every top-level key, or every
# instance field named like a formal, reds the controls here.
{
  genSchema,
  genMerge,
  prelude,
  ...
}:

let
  kindOf =
    args: decl:
    (genMerge.evalModuleTree { } [
      { options.schema = genSchema.mkSchemaOption args; }
      { config.schema.host = decl; }
    ]).config.schema.host;

  mkTypeArgs = {
    mkType =
      { kind, ... }:
      {
        inherit kind;
        custom = true;
      };
  };

  refuses = v: !(builtins.tryEval (builtins.deepSeq v v)).success;

  # THE POPULATION, read off the published `_reservedCollectionKeys`: the reserved collection set is
  # gen-merge's module keys ∪ its shorthand metadata ∪ the names gen-schema writes onto the kind
  # value ∪ the construction formals, so taking the module keys, the shorthand metadata and the
  # `_`-prefixed names back out leaves exactly the names the declaration-key door reserves — read
  # from the library's own bindings, so a formal added there is covered here with no second edit.
  schemaConfig =
    (genMerge.evalModuleTree { } [ { options.schema = genSchema.mkSchemaOption { }; } ]).config.schema;
  population = builtins.filter (
    k:
    !(prelude.hasPrefix "_" k)
    && !(builtins.elem k (schemaConfig._declarationKeys ++ genMerge.moduleSyntax.shorthandMeta))
  ) schemaConfig._reservedCollectionKeys;

  int0 = genMerge.mkOption {
    type = genMerge.types.int;
    default = 0;
  };
  instanceOf =
    decl:
    let
      schema = genSchema.evalSchema {
        modules = [ { config.schema.k = decl; } ];
      };
    in
    (genMerge.evalModuleTree { } [
      { options.ks = genSchema.mkInstanceRegistry schema.k { }; }
      { config.ks.a = { }; }
    ]).config.ks.a;
in
{
  flake.tests.construction-formals = {
    # G8 · every member refuses as SHORTHAND on BOTH branches. The value is the list of members that
    # did NOT refuse, so a member the door misses is named. `keySemantics` in the population and an
    # ordinary key admitted on both branches are the live controls: the first rules out a vacuous
    # population, the second a door that refuses everything.
    test-population-refuses-on-both-branches = {
      expr = {
        populationCarriesKeySemantics = builtins.elem "keySemantics" population;
        admittedDefault = builtins.filter (
          f: !(refuses (kindOf { } { ${f} = "x"; }).__mint.minted)
        ) population;
        admittedMkType = builtins.filter (
          f: !(refuses (kindOf mkTypeArgs { ${f} = "x"; }).custom)
        ) population;
        ordinaryDefault = refuses (kindOf { } { role = "x"; }).__mint.minted;
        ordinaryMkType = refuses (kindOf mkTypeArgs { role = "x"; }).custom;
      };
      expected = {
        populationCarriesKeySemantics = true;
        admittedDefault = [ ];
        admittedMkType = [ ];
        ordinaryDefault = false;
        ordinaryMkType = false;
      };
    };

    # G3/G4 · the routes that are not the misreading still write: an instance field named for a
    # formal, declared on the entry and set under `config.`, reaches the instance; so does an ordinary
    # declared field set as shorthand.
    test-instance-routes-still-write = {
      expr = {
        viaConfig =
          (instanceOf {
            options.keySemantics = int0;
            config.keySemantics = 3;
          }).keySemantics;
        ordinary =
          (instanceOf {
            imports = [ { options.priority = int0; } ];
            priority = 7;
          }).priority;
      };
      expected = {
        viaConfig = 3;
        ordinary = 7;
      };
    };

    # G9 · the door moves no mark of a kind that writes no formal: the clean kind's mark is the one it
    # minted before the door existed.
    test-clean-kind-mark-unmoved = {
      expr =
        (kindOf { } { options.role = genMerge.mkOption { type = genMerge.types.str; }; }).__mint.minted;
      expected = "schemakind:c169721a65681877bd243ac69b88eab4d51e86838217149f4e14278515a4aa95";
    };

    # ★ THE IMPORTS ROUTE IS REFUSED (den-hoag-8x97u). A formal at the top level of a module the entry
    # IMPORTS refuses at gen-merge's collector, which reads the entry defs' `entryReservation`; the
    # message is pinned in `ci/tests-error.nix` (`imports-route-refusals`). This cell was the
    # boundary pin while the route was residue, reading `false`.
    test-imported-formal-refused = {
      expr = refuses (kindOf { } { imports = [ { keySemantics = "x"; } ]; }).__mint.minted;
      expected = true;
    };

    # ★ THE BOUNDARY PIN for a CUSTOM `mkType` that builds instance modules from `defs` without
    # applying `entryReservation`: gen-schema cannot reach a module a caller-supplied function
    # builds, so the imports-route formal lands there, read back as config. `entryReservation` is the
    # supply route such a caller applies, as gen-aspects does. Pinned so a change to that boundary
    # is a visible decision.
    test-custom-mkType-without-the-reservation-still-lands = {
      expr =
        (kindOf {
          mkType =
            { kind, defs, ... }:
            {
              inherit kind;
              landed =
                (genMerge.evalModuleTree { } (
                  [
                    { options.keySemantics = genMerge.mkOption { type = genMerge.types.str; }; }
                  ]
                  ++ map (d: d.value) defs
                )).config.keySemantics;
            };
        } { imports = [ { keySemantics = "x"; } ]; }).landed;
      expected = "x";
    };
  };
}
