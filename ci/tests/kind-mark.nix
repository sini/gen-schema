# THE PROVENANCE MARK (ADR-0034) — the stamp, and the staging the admission read must preserve.
#
# `mkSchemaEntryType`'s merge mints `__mint.minted` over the kind's declared INERT surface, and the
# guards that used to admit any attrset with `? kind && ? options` now read that mark. The three
# things worth a cell are: both arms of the merge mint one; the read does not force the digest; and
# the SELF-REFERENTIAL idiom still evaluates, which is the property the whole shape is built around
# and the one nothing in this suite drove before.
{
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) mkSchemaOption mkInstanceRegistry;

  # The STANDARD arm — `mkSchemaOption` with no `mkType`, where `options` is populated.
  standardTree = genMerge.evalModuleTree {
    modules = [
      { options.schema = mkSchemaOption { }; }
      {
        config.schema.host = {
          options.role = genMerge.mkOption { type = genMerge.types.str; };
          options.port = genMerge.mkOption { type = genMerge.types.int; };
        };
      }
    ];
  };
  hostKind = standardTree.config.schema.host;

  # The mkTYPE arm — the door gen-aspects goes through (`gen-aspects/lib/schema.nix`, binding
  # `schemaOpt`), where the declarations live in the `__functor`'s imports. Both
  # shapes are covered because both reach ONE merge; the stamp is in that merge and nowhere else.
  mkTypeTree = genMerge.evalModuleTree {
    modules = [
      {
        options.schema = mkSchemaOption {
          mkType =
            {
              defs,
              kind,
              ...
            }:
            {
              __functor = _: _: {
                imports = map (d: d.value) defs;
              };
              inherit kind;
            };
        };
      }
      {
        config.schema.widget.options.facet = genMerge.mkOption { type = genMerge.types.str; };
      }
    ];
  };
  widgetKind = mkTypeTree.config.schema.widget;
in
{
  # O7. Both arms mint, and the cell pins the PREFIX rather than a literal digest: the digest is a
  # function of the fixture's own preimage, so pinning it would make every fixture edit look like a
  # mechanism change. What must hold is that a mark exists, is a string, and carries the
  # `"schemakind"` tag — disjoint from gen-algebra's `"its"`, which is what keeps the two namespaces
  # from colliding (`hashIdentity` refuses `:` in a kind name).
  flake.tests.kind-mark.test-both-entry-arms-mint-a-mark = {
    expr = {
      standardHasMark = hostKind ? __mint && hostKind.__mint ? minted;
      mkTypeHasMark = widgetKind ? __mint && widgetKind.__mint ? minted;
      standardPrefix = builtins.substring 0 11 hostKind.__mint.minted;
      mkTypePrefix = builtins.substring 0 11 widgetKind.__mint.minted;
      # The two arms mint DIFFERENT marks — a stamp that emitted one constant would satisfy every
      # presence arm above and separate nothing.
      armsDiffer = hostKind.__mint.minted != widgetKind.__mint.minted;
      # The mkType arm publishes the option plane its mark reads.
      mkTypeOptions = builtins.attrNames widgetKind.options;
    };
    expected = {
      standardHasMark = true;
      mkTypeHasMark = true;
      standardPrefix = "schemakind:";
      mkTypePrefix = "schemakind:";
      armsDiffer = true;
      mkTypeOptions = [ "facet" ];
    };
  };

  # The mark is a function of the DECLARED SURFACE, which is what makes it a mark rather than a
  # constant: a kind declaring one more option mints a different one. Without this, a stamp that
  # hashed only the kind NAME would pass every cell above — and a name is what `? options` already
  # was, one level down.
  flake.tests.kind-mark.test-the-mark-follows-the-declared-surface = {
    expr =
      let
        widened = genMerge.evalModuleTree {
          modules = [
            { options.schema = mkSchemaOption { }; }
            {
              config.schema.host = {
                options.role = genMerge.mkOption { type = genMerge.types.str; };
                options.port = genMerge.mkOption { type = genMerge.types.int; };
                options.zone = genMerge.mkOption { type = genMerge.types.str; };
              };
            }
          ];
        };
      in
      {
        movedOnAnExtraOption = widened.config.schema.host.__mint.minted != hostKind.__mint.minted;
        # LIVE CONTROL — the same declaration re-evaluated mints the SAME mark, so the arm above is
        # reading the surface and not merely the evaluation.
        stableAcrossEvaluations =
          (genMerge.evalModuleTree {
            modules = [
              { options.schema = mkSchemaOption { }; }
              {
                config.schema.host = {
                  options.role = genMerge.mkOption { type = genMerge.types.str; };
                  options.port = genMerge.mkOption { type = genMerge.types.int; };
                };
              }
            ];
          }).config.schema.host.__mint.minted == hostKind.__mint.minted;
      };
    expected = {
      movedOnAnExtraOption = true;
      stableAcrossEvaluations = true;
    };
  };

  # O6, EXTENDED — THE STAGING CELL, and it pins the read's reach in BOTH directions.
  #
  # The admission read is `v ? kind && v ? __mint && v.__mint ? minted`. It must force the mark
  # RECORD and stop there:
  #   · a kind value whose `minted` is a throw is ADMITTED and does not detonate — a builder who
  #     writes a recomputing or `.minted`-reading guard reds here, and that guard would re-hash at
  #     every admission and read caller data as its own comparand;
  #   · a kind value whose `__mint` is ITSELF a throw DOES detonate — a builder who writes the stamp
  #     as a thunk at `__mint` rather than a literal record with a thunk at `minted` reds here, and
  #     that stamp is what would deadlock the self-referential idiom below.
  # A cell carrying only the first arm passes on a `? __mint`-only predicate, which is measurably
  # no better than the `? options` this landing retires: a literal is a literal.
  flake.tests.kind-mark.test-admission-reads-the-record-and-not-the-digest = {
    expr = {
      thrownDigestIsAdmitted =
        (mkInstanceRegistry (
          hostKind
          // {
            __mint = {
              minted = throw "FORCED";
            };
          }
        ) { }).description;
      thrownMarkDetonates =
        !(builtins.tryEval
          (mkInstanceRegistry (hostKind // { __mint = throw "FORCED-MARK"; }) { }).description
        ).success;
      # LIVE CONTROL: the real kind value takes the same path and answers.
      realKindIsAdmitted = (mkInstanceRegistry hostKind { }).description;
    };
    expected = {
      thrownDigestIsAdmitted = "host instances";
      thrownMarkDetonates = true;
      realKindIsAdmitted = "host instances";
    };
  };

  # ★ THE DEFERRAL, DRIVEN AT THE REAL SITE — `options.hosts = mkInstanceRegistry config.schema.host
  # { }` declared in the SAME `evalModuleTree` as `config.schema.host`, which is the idiom
  # `lib/instance.nix` names verbatim where it explains why its guard is deferred.
  #
  # This is the property the mark's shape is built around, and nothing in this suite drove it before.
  # ★ `instance-registry.test-control-self-referential-registry-still-resolves` READS AS IF IT DID
  # AND DOES NOT: its schema comes out of a SEPARATE `evalSchema` call, so the kind is a finished
  # value before the registry option is declared and the deferral is never exercised. Measured, not
  # inferred — with the guard's assert hoisted out of its `kind` binding, THIS cell is the only one
  # in the suite that reds, and that one stays green.
  #
  # The failure is an UNCATCHABLE `infinite recursion`, so it cannot
  # be asserted with `tryEval` — the cell's value IS the assertion: if the deferral breaks, this cell
  # does not fail, it takes the whole evaluation down, which is loud in exactly the right way.
  flake.tests.kind-mark.test-self-referential-registry-still-evaluates = {
    expr =
      let
        selfReferential = genMerge.evalModuleTree {
          modules = [
            (
              { config, ... }:
              {
                options.schema = mkSchemaOption { };
                options.hosts = mkInstanceRegistry config.schema.host { };
                config.schema.host.options.role = genMerge.mkOption { type = genMerge.types.str; };
                config.hosts.igloo.role = "web";
              }
            )
          ];
        };
      in
      {
        instanceEvaluates = selfReferential.config.hosts.igloo.role;
        # The mark is reachable from the SAME eval, forced after the option phase rather than during
        # it. A stamp whose preimage could not be forced here would be a mark nothing may read.
        markIsForcibleInTheSameEval =
          builtins.substring 0 11
            selfReferential.config.schema.host.__mint.minted;
        # The instance still mints its own identity — `id_hash` and the mark are forced at the same
        # stratum, so a change that moved one would surface here rather than in a consumer.
        instanceMintsAnIdentity = builtins.substring 0 5 selfReferential.config.hosts.igloo.id_hash;
      };
    expected = {
      instanceEvaluates = "web";
      markIsForcibleInTheSameEval = "schemakind:";
      instanceMintsAnIdentity = "host:";
    };
  };
}
