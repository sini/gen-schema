# The canonical encoding — `hashIdentity`, the one minting authority.
#
# An identity is `"<kind>:" + sha256(<pairs preimage>)`, and the reference relation for the digest
# is the LANGUAGE'S `==`, in BOTH directions: the encoding is neither coarser nor finer than Nix
# equality. Each law below ships with a live positive control in the same run, because a law that
# can only be satisfied vacuously is not an oracle — an encoder that distinguishes everything
# passes every splitting assertion, and one that distinguishes nothing passes every merging one.
#
# The boundary discipline this file follows: a clause introducing a BOUNDARY owes a cell that
# STRADDLES it, not two cells that sit either side. The float domain's boundary is 2^53 and the
# straddling cell is the CROSS PAIR — an int and a float that Nix holds `==` across the bound. Two
# cells testing each side in isolation are both green while the bound is off by one.
{
  lib,
  genSchema,
  ...
}:
let
  inherit (genSchema) hashIdentity;

  pick = attrs: k: attrs.${k};

  # One label, one value — the scalar-law probe.
  idOf = v: hashIdentity "k" [ "x" ] (_: v);

  admits = e: (builtins.tryEval e).success;
  refuses = e: !(builtins.tryEval e).success;

  # 2^53 and its neighbours, written as expressions of the bound rather than as three unrelated
  # magic numbers, so the straddle stays a straddle if the bound ever moves.
  twoPow53 = 9007199254740992;
  ulpBelow = 9007199254740991;
  abovePow53 = 9007199254740993;
in
{
  ## `==` merges — the encoding is not FINER than Nix equality.

  # `toJSON` alone splits these (`"1"` vs `"1.0"`); the integral-float normalisation is what merges
  # them, and it is the only thing raw `toJSON` needed.
  flake.tests.identity-encoding.test-merges-int-and-integral-float = {
    expr = idOf 1 == idOf 1.0;
    expected = true;
  };
  # The same merge at the largest admissible magnitude, where the normalisation is load-bearing
  # rather than incidental.
  flake.tests.identity-encoding.test-merges-at-largest-admissible-magnitude = {
    expr = idOf ulpBelow == idOf (ulpBelow + 0.0);
    expected = true;
  };
  # CONTROL for the merging laws: an encoder that merged everything would pass them all.
  flake.tests.identity-encoding.test-control-distinct-ints-split = {
    expr = idOf 1 == idOf 2;
    expected = false;
  };

  ## `==` splits — the encoding is not COARSER than Nix equality.

  # JSON separates the scalar types natively; no discriminating type tag is needed.
  flake.tests.identity-encoding.test-splits-int-and-string = {
    expr = idOf 1 == idOf "1";
    expected = false;
  };
  flake.tests.identity-encoding.test-splits-bool-and-int = {
    expr = idOf true == idOf 1;
    expected = false;
  };
  flake.tests.identity-encoding.test-splits-bool-and-string = {
    expr = idOf true == idOf "true";
    expected = false;
  };
  # Finer than `toString`, which is coarser than `==` in the OTHER direction — it collapses
  # distinct doubles at six decimal places. This is why nothing renders through it.
  flake.tests.identity-encoding.test-finer-than-toString-on-floats = {
    expr = idOf 1.0000001 == idOf 1.0000002;
    expected = false;
  };
  # CONTROL for the splitting laws: an encoder that split everything would pass them all. The pair
  # above is `==`-distinct, and `toString` is measurably the coarser rendering.
  flake.tests.identity-encoding.test-control-those-floats-are-distinct-but-toString-collapses-them = {
    expr = {
      nixDistinct = 1.0000001 != 1.0000002;
      toStringCollapses = toString 1.0000001 == toString 1.0000002;
      sameFloatMerges = idOf 1.0000001 == idOf 1.0000001;
    };
    expected = {
      nixDistinct = true;
      toStringCollapses = true;
      sameFloatMerges = true;
    };
  };

  ## The float domain — `|v| < 2^53`, STRICT — and the cross pair that straddles its boundary.

  # Nix's `==` is not an equivalence relation across int and float above 2^53: two ints that are
  # NOT equal to each other are both equal to one float. The ruled biconditional has no model
  # there, so the domain stops where it stops having one.
  flake.tests.identity-encoding.test-bound-float-refused = {
    expr = refuses (idOf (twoPow53 + 0.0));
    expected = true;
  };
  flake.tests.identity-encoding.test-negative-bound-float-refused = {
    expr = refuses (idOf (0.0 - (twoPow53 + 0.0)));
    expected = true;
  };
  # THE STRADDLING CELL. `abovePow53` (int) and `twoPow53` (float) are `==` in Nix, so they must not
  # both be admissible with different digests. The strict bound removes the float side — and it is
  # the ONLY such pair, which is what leaves ints unrestricted. An INCLUSIVE bound admits both and
  # mints them differently: the identity law failing inside its own declared domain.
  flake.tests.identity-encoding.test-cross-pair-not-both-admissible = {
    expr = admits (idOf abovePow53) && refuses (idOf (twoPow53 + 0.0));
    expected = true;
  };
  flake.tests.identity-encoding.test-negative-cross-pair-not-both-admissible = {
    expr = admits (idOf (0 - abovePow53)) && refuses (idOf (0.0 - (twoPow53 + 0.0)));
    expected = true;
  };
  # CONTROLS for the straddle: the pair really is `==` (else the cell tests nothing), and one ULP
  # below the bound the same two shapes are both admitted and MERGE (else the refusal is not
  # buying a law, it is just a refusal).
  flake.tests.identity-encoding.test-control-cross-pair-is-nix-equal = {
    expr = {
      acrossTheBound = abovePow53 == (twoPow53 + 0.0);
      atTheBound = twoPow53 == (twoPow53 + 0.0);
      andTheIntsDiffer = abovePow53 == twoPow53;
    };
    expected = {
      acrossTheBound = true;
      atTheBound = true;
      andTheIntsDiffer = false;
    };
  };
  flake.tests.identity-encoding.test-control-one-ulp-below-both-admitted-and-merging = {
    expr = {
      bothAdmitted = admits (idOf ulpBelow) && admits (idOf (ulpBelow + 0.0));
      theyMerge = idOf ulpBelow == idOf (ulpBelow + 0.0);
    };
    expected = {
      bothAdmitted = true;
      theyMerge = true;
    };
  };
  # Ints are unrestricted, and still split from each other above the bound.
  flake.tests.identity-encoding.test-big-ints-admitted-and-split = {
    expr = {
      admitted = admits (idOf abovePow53) && admits (idOf twoPow53);
      split = idOf abovePow53 == idOf twoPow53;
    };
    expected = {
      admitted = true;
      split = false;
    };
  };
  # A float far outside the range refuses BY NAME rather than aborting: `builtins.floor` throws
  # outside NixInt range and `tryEval` cannot catch that, so the range test must run first.
  flake.tests.identity-encoding.test-out-of-range-float-refused-catchably = {
    expr = refuses (idOf 1.0e30);
    expected = true;
  };
  flake.tests.identity-encoding.test-infinity-refused-catchably = {
    expr = refuses (idOf (1.0e308 * 10.0));
    expected = true;
  };
  flake.tests.identity-encoding.test-control-in-range-float-admitted = {
    expr = admits (idOf 1.5) && admits (idOf (ulpBelow + 0.0));
    expected = true;
  };

  ## Separator injection — closed in two regions, by two different mechanisms.

  # Inside the pairs preimage, by SELF-DELIMITATION: JSON quotes string values and escapes internal
  # quotes and backslashes, so no value can synthesise a structural boundary and forge a different
  # key arity.
  flake.tests.identity-encoding.test-separator-injection-closed = {
    expr =
      hashIdentity "aspect"
        [
          "origin"
          "key"
        ]
        (pick {
          origin = "x";
          key = "y";
        })
      == hashIdentity "aspect" [ "origin" ] (pick { origin = "x|key=y"; });
    expected = false;
  };
  flake.tests.identity-encoding.test-control-same-input-mints-equal = {
    expr =
      hashIdentity "aspect"
        [
          "origin"
          "key"
        ]
        (pick {
          origin = "x";
          key = "y";
        })
      == hashIdentity "aspect"
        [
          "origin"
          "key"
        ]
        (pick {
          origin = "x";
          key = "y";
        });
    expected = true;
  };
  # A VALUE may contain a colon and a KIND may not — data is escaped, structure is constrained.
  # This is not academic: relatum values ARE identities, and an identity carries a colon.
  flake.tests.identity-encoding.test-colon-in-value-admitted-and-still-splitting = {
    expr = {
      admitted = admits (idOf "sha256:aaa");
      stillSplits = idOf "sha256:aaa" == idOf "sha256:bbb";
    };
    expected = {
      admitted = true;
      stillSplits = false;
    };
  };

  ## Order-freedom — the permutation law, by construction rather than by a caller's sort.

  # The pairs are rendered as an ATTRSET; attrsets carry no order. A caller's list order therefore
  # cannot reach the digest, so an unsorted caller is a non-event rather than a latent defect.
  flake.tests.identity-encoding.test-label-order-free = {
    expr = {
      hostUser =
        hashIdentity "k"
          [
            "host"
            "user"
          ]
          (pick {
            host = "H";
            user = "U";
          })
        == hashIdentity "k"
          [
            "user"
            "host"
          ]
          (pick {
            host = "H";
            user = "U";
          });
      originKey =
        hashIdentity "aspect"
          [
            "origin"
            "key"
          ]
          (pick {
            origin = "o";
            key = "k";
          })
        == hashIdentity "aspect"
          [
            "key"
            "origin"
          ]
          (pick {
            origin = "o";
            key = "k";
          });
      # The hole-filled shape: a literal pair followed by appended keys that sort before both.
      withHoles =
        hashIdentity "aspect"
          [
            "origin"
            "key"
            "hole:a"
            "hole:b"
          ]
          (pick {
            origin = "o";
            key = "k";
            "hole:a" = "1";
            "hole:b" = "2";
          })
        == hashIdentity "aspect"
          [
            "hole:b"
            "key"
            "hole:a"
            "origin"
          ]
          (pick {
            origin = "o";
            key = "k";
            "hole:a" = "1";
            "hole:b" = "2";
          });
    };
    expected = {
      hostUser = true;
      originKey = true;
      withHoles = true;
    };
  };
  # CONTROLS. `differentKeySets` guards against an encoder that ignores labels entirely;
  # `swappedValues` guards against the degenerate pass where order-freedom is bought by losing the
  # label↔value association along with the order.
  flake.tests.identity-encoding.test-control-order-freedom-is-not-blindness = {
    expr = {
      differentKeySets =
        hashIdentity "k"
          [
            "host"
            "user"
          ]
          (pick {
            host = "H";
            user = "U";
          })
        == hashIdentity "k" [ "host" ] (pick { host = "H"; });
      swappedValues =
        hashIdentity "k"
          [
            "host"
            "user"
          ]
          (pick {
            host = "H";
            user = "U";
          })
        == hashIdentity "k"
          [
            "host"
            "user"
          ]
          (pick {
            host = "U";
            user = "H";
          });
    };
    expected = {
      differentKeySets = false;
      swappedValues = false;
    };
  };

  ## The kind tag rides OUTSIDE the digest.

  flake.tests.identity-encoding.test-identity-is-kind-prefix-and-digest = {
    expr = builtins.match "owns:[0-9a-f]{64}" (hashIdentity "owns" [ "a" ] (_: 1)) != null;
    expected = true;
  };
  # The kind is recoverable by splitting on the first colon, with no reverse lookup. This is the
  # shape the retiring standalone minter had, and the reason the rider refuses `:` in a kind.
  flake.tests.identity-encoding.test-kind-recoverable-by-first-colon = {
    expr = builtins.head (lib.splitString ":" (hashIdentity "owns" [ "a" ] (_: 1)));
    expected = "owns";
  };
  flake.tests.identity-encoding.test-kind-prefix-shape = {
    expr = builtins.substring 0 5 (hashIdentity "owns" [ "a" ] (_: 1));
    expected = "owns:";
  };
  flake.tests.identity-encoding.test-kind-separates-relations = {
    expr = hashIdentity "owns" [ "a" ] (_: 1) == hashIdentity "runs" [ "a" ] (_: 1);
    expected = false;
  };
  flake.tests.identity-encoding.test-control-same-kind-mints-equal = {
    expr = hashIdentity "owns" [ "a" ] (_: 1) == hashIdentity "owns" [ "a" ] (_: 1);
    expected = true;
  };
  # The ACCEPTED consequence, asserted rather than left implicit: two relations over identical
  # relata share a digest REGION. The identity is the WHOLE STRING — its control is directly below
  # — so a consumer that slices the digest out is not comparing identities.
  flake.tests.identity-encoding.test-digest-region-is-kind-independent = {
    expr =
      builtins.substring 5 64 (hashIdentity "owns" [ "a" ] (_: 1))
      == builtins.substring 5 64 (hashIdentity "runs" [ "a" ] (_: 1));
    expected = true;
  };
  flake.tests.identity-encoding.test-control-whole-identities-still-differ = {
    expr = hashIdentity "owns" [ "a" ] (_: 1) == hashIdentity "runs" [ "a" ] (_: 1);
    expected = false;
  };

  ## The kind separator is refused in a kind name — the join's half of the injection class.

  flake.tests.identity-encoding.test-colon-in-kind-refused = {
    expr = {
      interior = refuses (hashIdentity "own:s" [ "a" ] (_: 1));
      leading = refuses (hashIdentity ":owns" [ "a" ] (_: 1));
      trailing = refuses (hashIdentity "owns:" [ "a" ] (_: 1));
      # STRADDLES the negated-character-class edge. `builtins.match` anchors the whole string, so
      # `[^:]*` asserts TOTALITY — every character is a non-colon — and no position escapes it,
      # which is what makes the guard exhaustive rather than a search that could stop early. The
      # edge worth pinning is whether the class quantifies across a LINE boundary, since that is
      # where guards commonly go line-oriented; this cell holds one side (a colon after a newline
      # is still caught) and `newlineOnly` below holds the other (a newline alone is admitted).
      afterNewline = refuses (hashIdentity "owns\nother:x" [ "a" ] (_: 1));
    };
    expected = {
      interior = true;
      leading = true;
      trailing = true;
      afterNewline = true;
    };
  };
  # CONTROLS for the rider, including the other side of the newline straddle: a newline alone is
  # not a colon and must still be admitted, else the guard is refusing the wrong thing.
  flake.tests.identity-encoding.test-control-colon-free-kinds-admitted = {
    expr = {
      identifierLike = admits (hashIdentity "attaches" [ "a" ] (_: 1));
      newlineOnly = admits (hashIdentity "owns\nother" [ "a" ] (_: 1));
      plain = admits (hashIdentity "owns" [ "a" ] (_: 1));
    };
    expected = {
      identifierLike = true;
      newlineOnly = true;
      plain = true;
    };
  };
  # What the rider protects: with a colon-bearing kind, first-colon recovery returns the WRONG tag.
  flake.tests.identity-encoding.test-unguarded-join-would-mis-recover-the-kind = {
    expr = builtins.head (lib.splitString ":" "a:b:0000");
    expected = "a";
  };

  ## The structural refusals — each by name, each with a live counterpart that is admitted.

  flake.tests.identity-encoding.test-empty-kind-refused = {
    expr = refuses (hashIdentity "" [ "a" ] (_: 1));
    expected = true;
  };
  flake.tests.identity-encoding.test-zero-labels-refused = {
    expr = refuses (hashIdentity "k" [ ] (_: 1));
    expected = true;
  };
  # Forced by the attrset construction: `listToAttrs` would SILENTLY collapse a repeated label,
  # trading an order defect for an arity defect. The refusal is checked on the LABEL LIST, before
  # any value is forced, so the error names the structural mistake and not a symptom of it.
  flake.tests.identity-encoding.test-duplicate-label-refused = {
    expr = refuses (
      hashIdentity "k" [
        "a"
        "a"
      ] (_: 1)
    );
    expected = true;
  };
  flake.tests.identity-encoding.test-control-structural-counterparts-admitted = {
    expr = {
      namedKind = admits (hashIdentity "k" [ "a" ] (_: 1));
      oneLabel = admits (hashIdentity "k" [ "a" ] (_: 1));
      distinctLabels = admits (
        hashIdentity "k"
          [
            "a"
            "b"
          ]
          (pick {
            a = 1;
            b = 2;
          })
      );
    };
    expected = {
      namedKind = true;
      oneLabel = true;
      distinctLabels = true;
    };
  };

  ## Non-scalar values — refused by a PREDICATE, because the encoder's own failure is uncatchable.

  # `builtins.toJSON` on a function aborts the evaluation and escapes `tryEval` entirely: the
  # message names JSON, not the kind, the label or the emitter. Admitting values by predicate first
  # converts that into a `throw` a caller can attribute and a test can assert on — which is what
  # the `function` cell here proves, since it could not be written at all otherwise.
  flake.tests.identity-encoding.test-non-scalar-values-refused = {
    expr = {
      attrs = refuses (idOf { a = 1; });
      null_ = refuses (idOf null);
      list = refuses (idOf [ 1 ]);
      function = refuses (idOf (y: y));
      path = refuses (idOf ./.);
    };
    expected = {
      attrs = true;
      null_ = true;
      list = true;
      function = true;
      path = true;
    };
  };
  flake.tests.identity-encoding.test-control-scalars-admitted = {
    expr = {
      string = admits (idOf "s");
      int = admits (idOf 1);
      bool = admits (idOf true);
      float = admits (idOf 1.5);
    };
    expected = {
      string = true;
      int = true;
      bool = true;
      float = true;
    };
  };
  # CONTROL on the instrument itself: `tryEval` catches a named `throw` in this very run, so a
  # `refuses` cell above reports a refusal rather than an unrelated evaluation failure.
  flake.tests.identity-encoding.test-control-tryEval-catches-a-named-throw = {
    expr = refuses (throw "boom") && admits "fine";
    expected = true;
  };

  ## The worked example — the preimage a reader can check by hand.

  # The caller supplies `[ "user" "host" ]` and the preimage comes out `host` before `user`: the
  # sort happened inside the attrset, not in the caller. The relatum values carry colons and are
  # unaffected — the colon refusal constrains the KIND only.
  flake.tests.identity-encoding.test-worked-example = {
    expr =
      hashIdentity "owns"
        [
          "user"
          "host"
        ]
        (pick {
          user = "sha256:aaa";
          host = "sha256:bbb";
        });
    expected =
      "owns:"
      + builtins.hashString "sha256" ''{"host":"sha256:bbb","user":"sha256:aaa"}'';
  };
}
