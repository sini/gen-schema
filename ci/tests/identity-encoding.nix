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

  # ── fixtures for the two bounds ──
  #
  # Three shapes, because the three axes are independent and each is refused by a different bound.
  # A CYCLE has unbounded depth and a slowly-growing preimage; a thin CHAIN has a small preimage
  # and whatever depth it is given; a shared DAG has small depth and an expansion exponential in
  # it. `sharedDag n` binds each level ONCE and references it twice, which is how Nix represents
  # ordinary values — n+2 distinct nodes, 2^n expansion.
  cyclicRecord = {
    self = cyclicRecord;
    leaf = 1;
  };
  chain = n: if n == 0 then { leaf = 1; } else { next = chain (n - 1); };
  sharedDag =
    n:
    if n == 0 then
      { leaf = 1; }
    else
      let
        shared = sharedDag (n - 1);
      in
      {
        a = shared;
        b = shared;
      };
  flatRecord100 = builtins.listToAttrs (
    builtins.genList (i: {
      name = "k${builtins.toString i}";
      value = i;
    }) 100
  );

  # ── fixtures for the BREADTH axis ──
  #
  # A list of `n` nulls encodes at exactly two characters a member (`z` and its separator), inside a
  # frame costing nine, so its preimage is 2n + 9 and the budget's own arithmetic fixes the
  # boundary: 32,763 members mint at 65,535 characters and 32,764 refuse at 65,537. Written as
  # expressions of the budget rather than as magic numbers, so the straddle survives the bound
  # moving.
  wideList = n: builtins.genList (_: null) n;
  wideRecord =
    n:
    builtins.listToAttrs (
      builtins.genList (i: {
        name = "k${builtins.toString i}";
        value = null;
      }) n
    );
  # WIDE AND DEEP together: breadth inside the fold at every one of many levels, which is the shape
  # a per-step force could plausibly still have failed on.
  wideAndDeep =
    d: w:
    let
      go = k: if k == 0 then null else builtins.genList (_: go (k - 1)) w;
    in
    go d;

  # ── fixtures for the derivation gate ──
  #
  # `drvShaped` is HAND-WRITTEN to the shape the gate tests — all three attributes — which makes it a
  # fixture for the PREDICATE and not for the hazard. `typeOnly` carries the word alone, which is an
  # ordinary declaration a `str` option may hold.
  drvShaped = {
    type = "derivation";
    drvPath = "/nix/store/0000000000000000000000000000000-probe.drv";
    outPath = "/nix/store/1111111111111111111111111111111-probe";
  };
  typeOnly = {
    type = "derivation";
    n = 1;
  };

  # ★ AND A REAL ONE, because the hand-written record cannot carry the property the gate exists for.
  # What does not terminate under an unbounded walk is a derivation's SELF-REFERENTIAL output
  # attribute — `drv.out.out.out.name` resolves — and no hand-written fixture has it. Built with the
  # `derivation` builtin rather than through nixpkgs: it needs no search path, and a fixture whose
  # construction can silently fail turns its own refusal cell into an import error wearing a
  # refusal's clothes.
  realDerivation = derivation {
    name = "identity-encoding-probe";
    system = "x86_64-linux";
    builder = "/bin/sh";
  };
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
        }) == hashIdentity "aspect" [ "origin" ] (pick {
        origin = "x|key=y";
      });
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
        }) == hashIdentity "aspect"
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
          }) == hashIdentity "k"
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
          }) == hashIdentity "aspect"
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
          }) == hashIdentity "aspect"
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
          }) == hashIdentity "k" [ "host" ] (pick {
          host = "H";
        });
      swappedValues =
        hashIdentity "k"
          [
            "host"
            "user"
          ]
          (pick {
            host = "H";
            user = "U";
          }) == hashIdentity "k"
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

  ## The DOMAIN — inert structure is admitted; what cannot be walked is refused BY A PREDICATE,
  ## because the encoder's own failure is not a refusal.

  # `builtins.toJSON` on a function aborts the evaluation and escapes `tryEval` entirely: the
  # message names JSON, not the kind, the label or the emitter. Admitting values by predicate first
  # converts that into a `throw` a caller can attribute and a test can assert on — which is what
  # the `function` cell here proves, since it could not be written at all otherwise.
  #
  # A DERIVATION is refused by a type test before any descent: its output attribute is
  # self-referential, so an unbounded walk over one does not terminate. The gate is narrow and
  # exists for TERMINATION — see `test-outPath-record-is-exact` for the non-derivation record that
  # merely carries `outPath` and is encoded structurally.
  flake.tests.identity-encoding.test-non-inert-values-refused = {
    expr = {
      function = refuses (idOf (y: y));
      path = refuses (idOf ./.);
      # The FULL three-attribute shape, which is what an actual derivation carries. The gate tests
      # all three so a record merely HOLDING the word stays admissible at every depth — see
      # `test-derivation-gate-does-not-depend-on-position`.
      derivation = refuses (idOf drvShaped);
      nestedFunction = refuses (idOf {
        a = [ { f = y: y; } ];
      });
    };
    expected = {
      function = true;
      path = true;
      derivation = true;
      nestedFunction = true;
    };
  };

  # THE DOMAIN EXTENSION. These three were refusals under the scalar-only encoder, and the
  # refusal was the thing that made "identity of substrate-constructed things is structural"
  # unreachable: a reified record is an attrset and a list of components is a list, so neither
  # could enter the mint at all. They are admissions now, and every one of them mints EXACTLY —
  # the splitting laws above range over the whole admitted domain, not over its scalar part.
  flake.tests.identity-encoding.test-inert-composites-admitted = {
    expr = {
      attrs = admits (idOf {
        a = 1;
      });
      null_ = admits (idOf null);
      list = admits (idOf [ 1 ]);
      nested = admits (idOf [
        1
        {
          b = "s";
        }
        null
      ]);
    };
    expected = {
      attrs = true;
      null_ = true;
      list = true;
      nested = true;
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

  ## FORGERY IS INEXPRESSIBLE — the arm is armed on the channel that broke the delegated encoding.

  # A type tag on every node is what makes a forgery unsayable rather than blocked case by case.
  # Without the tags, a caller-supplied STRING could render byte-identically to a composite and
  # steal its identity. Each pair below is a string on one side and the structure it would have
  # imitated on the other.
  flake.tests.identity-encoding.test-forgery-is-inexpressible = {
    expr = {
      stringVsList = idOf "[i1]" == idOf [ 1 ];
      stringVsAttrs = idOf ''{"a":i1}'' == idOf { a = 1; };
      keyVsPair =
        idOf {
          "a\":sx" = null;
        } == idOf { a = "sx"; };
    };
    expected = {
      stringVsList = false;
      stringVsAttrs = false;
      keyVsPair = false;
    };
  };

  # THE `outPath` CHANNEL, which is what forced the encoder to emit structure itself rather than
  # delegate it. A NON-DERIVATION record carrying `outPath` is ordinary data and must mint exactly.
  flake.tests.identity-encoding.test-outPath-record-is-exact = {
    expr =
      let
        a = idOf {
          outPath = "x";
          a = 1;
        };
        b = idOf {
          outPath = "x";
          a = 2;
        };
        bare = idOf "x";
      in
      {
        siblingsDiscriminate = a == b;
        neitherEqualsTheBareString = a == bare || b == bare;
      };
    expected = {
      siblingsDiscriminate = false;
      neitherEqualsTheBareString = false;
    };
  };

  # RED CONTROL, and it must stay red against the delegated encoding: raw `toJSON` collapses all
  # three of those values to the same rendering. A run in which this control does not reproduce the
  # collapse has not tested the cell above — it would pass against an encoder that never had the
  # defect, and there would be nothing to show the defect was real.
  flake.tests.identity-encoding.test-control-raw-toJSON-collapses-outPath = {
    expr =
      let
        a = builtins.toJSON {
          outPath = "x";
          a = 1;
        };
        b = builtins.toJSON {
          outPath = "x";
          a = 2;
        };
      in
      a == b && a == builtins.toJSON "x";
    expected = true;
  };

  ## THE THREE AXES — length, depth, and BREADTH — each refusing by name, each catchable.

  # DEPTH. A cyclic value has unbounded depth, and no builtin can decide "reachable from itself" —
  # structural `==` on one diverges for the same reason a walk would. The bound converts that
  # undetectable divergence into a NAMED, CATCHABLE refusal, which is the only form the mint
  # admits. The over-deep thin CHAIN is the same bound firing on a value that is not cyclic at all.
  flake.tests.identity-encoding.test-depth-bound-refuses-catchably = {
    expr = {
      cyclic = refuses (idOf cyclicRecord);
      deepChain = refuses (idOf (chain 1000));
    };
    expected = {
      cyclic = true;
      deepChain = true;
    };
  };

  # ★ THE BOUNDS ARE INDEPENDENT, AND THIS IS THE CELL THAT SHOWS IT IN-SUITE. A 515-deep chain's
  # preimage is about ten characters a level — some five thousand, comfortably inside the length
  # budget — so a run in which it refuses has refused on DEPTH and not on length.
  #
  # ★★ AND FOR A CYCLE THE DEPTH BOUND IS NOT MERELY FIRST — IT IS THE ONLY GUARD. Stated
  # precisely, because an earlier reading here said the two bounds OVERLAP on a cyclic value and
  # that it "refuses catchably either way", which is the kind of claim that reads true and measures
  # false.
  #
  # TWO CONSTANTS, and they belong to DIFFERENT SHAPES — conflating them is what produced the wrong
  # figure. The cyclic record's level costs 18 characters DESCENDING (`{"leaf":i1,"self":`) and 2
  # more ASCENDING (`,}`). A FINITE record of that shape therefore costs 20 a level — measured,
  # preimage lengths 19 · 39 · 59 · … · 219 at depths 0 · 1 · 2 · … · 10 — so 65,536/20 ≈ 3,276.
  # But A CYCLE NEVER ASCENDS, so it never pays the closers and its own crossover would be
  # 65,536/18 ≈ 3,641. The earlier figure divided the budget by the finite record's constant to
  # predict where a cycle exhausts it, which is two different quantities.
  #
  # ★ AND THE CYCLE'S CROSSOVER IS UNREACHABLE. Measured, budget held at the shipped 65,536 and the
  # DEPTH bound swept: at 512, 3,000, 3,300 and 3,320 the cycle refuses CATCHABLY by name; at 3,340
  # and above it aborts UNCATCHABLY with `stack overflow; max-call-depth exceeded`. The call-depth
  # guard therefore bites in the low 3,300s, BELOW the ~3,641 the length bound would have needed —
  # so no depth setting exists at which length saves a cycle. Nothing but the depth bound stands
  # between a cyclic value and an uncatchable abort, which is a stronger reason to keep it than the
  # overlap story it replaces. (The crossover is given as an interval on purpose: `max-call-depth`
  # counts a GLOBAL frame budget, so the exact level moves with whatever else the run is holding.)
  #
  # The boundary is STRADDLED rather than tested from one side: 510 mints and 515 refuses, so the
  # cell still means something if the bound ever moves.
  flake.tests.identity-encoding.test-depth-bound-straddles-its-boundary = {
    expr = {
      justUnder = admits (idOf (chain 510));
      justOver = refuses (idOf (chain 515));
    };
    expected = {
      justUnder = true;
      justOver = true;
    };
  };

  # LENGTH. Sharing is how Nix represents ordinary values, and what a walk pays is the EXPANSION,
  # not the distinct-node count: a depth-d shared DAG has d+2 distinct nodes and a 2^d expansion.
  # The budget refuses WITHOUT DOING THE EXPONENTIAL WORK — depth 20, 24 and 30 all refuse, and
  # they refuse in budget time rather than after the expansion is built.
  #
  # ★ This is the design's PRICE and it is named rather than hidden: a value with FEW DISTINCT
  # NODES is refused when its expansion exceeds the budget.
  flake.tests.identity-encoding.test-length-budget-refuses-shared-expansion = {
    expr = {
      depth20 = refuses (idOf (sharedDag 20));
      depth24 = refuses (idOf (sharedDag 24));
      depth30 = refuses (idOf (sharedDag 30));
    };
    expected = {
      depth20 = true;
      depth24 = true;
      depth30 = true;
    };
  };

  # CONTROLS for both bounds, and they are required rather than decorative: an encoder that refused
  # EVERYTHING would pass every refusal cell above. A shallow shared DAG mints, a 200-deep thin
  # chain mints (the budget refuses on COST, not on shape), and a 100-key flat record — the shape
  # an ordinary identity preimage actually has — mints.
  flake.tests.identity-encoding.test-control-bounded-values-still-mint = {
    expr = {
      shallowDag = admits (idOf (sharedDag 8));
      thinChain = admits (idOf (chain 200));
      flatRecord = admits (idOf flatRecord100);
    };
    expected = {
      shallowDag = true;
      thinChain = true;
      flatRecord = true;
    };
  };

  # ★★ BREADTH — the axis neither declared bound reaches, and the one that escaped both. A wide
  # value sits INSIDE the length budget and INSIDE the depth bound and still killed the evaluation:
  # measured before the fix, a 31,000-element list (62,009 preimage characters, two levels deep)
  # aborted with `stack overflow` ESCAPING `tryEval`, and so did a list whose preimage was over
  # budget — the budget could not refuse it because the budget was itself still an unforced thunk.
  #
  # The bounds were never too loose; they had not been EVALUATED. `encodeComposite` forces both
  # accumulator fields at every step, which is what makes the length budget bite on this axis at
  # all. A wide value now either MINTS or REFUSES BY NAME, and never aborts.
  flake.tests.identity-encoding.test-breadth-is-bounded-and-never-aborts = {
    expr = {
      wideMints = admits (idOf (wideList 31000));
      widerRefuses = refuses (idOf (wideList 40000));
      # the RECORD arm takes the same fold, so it owes the same evidence as the LIST arm
      wideRecordMints = admits (idOf (wideRecord 4000));
      # wide AND deep at once — many levels, each one a fold over many members
      wideAndDeepRefuses = refuses (idOf (wideAndDeep 400 40));
    };
    expected = {
      wideMints = true;
      widerRefuses = true;
      wideRecordMints = true;
      wideAndDeepRefuses = true;
    };
  };

  # The breadth boundary STRADDLED, and it is the length budget's own arithmetic: a null member
  # costs two characters and the frame costs nine, so 2n + 9 crosses 65,536 between these two.
  # A refusal here is the NAMED budget refusal — the same one a long preimage gets — which is what
  # shows breadth is bounded BY the length bound rather than by a bound of its own.
  flake.tests.identity-encoding.test-breadth-straddles-the-budget-boundary = {
    expr = {
      justUnder = admits (idOf (wideList 32763));
      justOver = refuses (idOf (wideList 32764));
    };
    expected = {
      justUnder = true;
      justOver = true;
    };
  };

  ## THE DERIVATION GATE — refusal by shape, and it must not depend on POSITION.

  # ★ A value the encoder admits at one depth and refuses at another is not a domain. Testing `type`
  # alone did exactly that: a record whose `type` field merely held the string "derivation" minted as
  # the mint's own outer frame — which is not caller data and skips the gate — and refused one level
  # down. Requiring the full three-attribute shape makes admissibility a property of the VALUE.
  #
  # CONTROL, in the same cell: the identical shape carrying an ordinary `type` mints at both
  # positions, so the cell is about the gate and not about the two positions differing generally.
  flake.tests.identity-encoding.test-derivation-gate-does-not-depend-on-position = {
    expr = {
      atFrame = admits (hashIdentity "k" [ "type" "n" ] (pick typeOnly));
      nested = admits (idOf typeOnly);
      controlOrdinaryAtFrame = admits (
        hashIdentity "k" [ "type" "n" ] (pick {
          type = "ordinary";
          n = 1;
        })
      );
      controlOrdinaryNested = admits (idOf {
        type = "ordinary";
        n = 1;
      });
    };
    expected = {
      atFrame = true;
      nested = true;
      controlOrdinaryAtFrame = true;
      controlOrdinaryNested = true;
    };
  };

  # And the value the gate EXISTS for is still refused, wherever caller data can put it. A
  # derivation's output attribute is self-referential, so an unbounded walk over one does not
  # terminate — the gate is what turns that into a named refusal, and narrowing it above must not
  # have opened it.
  #
  # ★ The mint's own outer FRAME is the one position this does not range over, and that is the
  # design rather than a gap: the frame is synthesized by the mint out of a kind's scalar option
  # values, so it cannot be a derivation whatever its labels are named. A kind whose identity keys
  # happen to be `type`, `drvPath` and `outPath` therefore mints, and the arm below states that
  # rather than leaving it to be discovered.
  flake.tests.identity-encoding.test-derivation-shape-refused-wherever-caller-data-reaches = {
    expr = {
      nested = refuses (idOf drvShaped);
      deep = refuses (idOf {
        a = [ drvShaped ];
      });
      inAList = refuses (idOf [ drvShaped ]);
      frameOfThoseLabelsStillMints = admits (
        hashIdentity "k" [ "type" "drvPath" "outPath" ] (pick drvShaped)
      );
    };
    expected = {
      nested = true;
      deep = true;
      inAList = true;
      frameOfThoseLabelsStillMints = true;
    };
  };

  # ★★ THE HAZARD ITSELF, not a hand-written likeness of it. Every derivation cell above uses a
  # record built to the gate's own predicate, which can only show the predicate fires — it cannot
  # show the predicate catches the thing it was written for, because a hand-written record has no
  # self-referential output attribute and would walk to a finite end anyway.
  #
  # POSITIVE CONTROL FIRST, and it is required rather than decorative: the fixture must actually BE
  # a derivation — all three attributes present AND `out.out.out.name` resolving — or its refusal
  # below is unattributable. A fixture whose construction fails silently reads exactly like a value
  # the gate refused, which is the failure mode this control exists to exclude. (An earlier probe of
  # this property used a nixpkgs import that did not resolve on the machine it ran on, and its
  # "refusal" was an import error; this control is what caught that, and why it is written first.)
  #
  # ★ WHAT THIS CELL PINS, AND WHAT IT DOES NOT — measured by seeding, not assumed. Seeding the gate
  # away ALONE leaves every arm green: the depth bound catches the self-referential walk instead, so
  # the value is still refused catchably. Seeding away the gate AND the depth bound together makes
  # the same value abort UNCATCHABLY, with a clean value still minting in that build. ⇒ This cell
  # pins "a real derivation is REFUSED, and never aborts" — which is the property ADR-0034's
  # excluded-population clause actually needs — and it does NOT attribute the refusal to the gate,
  # because `tryEval` reports catchability and not which named throw fired. The gate's own
  # contribution is pinned by the position cells above, where the depth bound cannot stand in.
  flake.tests.identity-encoding.test-real-derivation-refused-by-name = {
    expr = {
      controlFixtureIsADerivation =
        (realDerivation.type or null) == "derivation"
        && realDerivation ? drvPath
        && realDerivation ? outPath;
      controlFixtureIsSelfReferential = admits realDerivation.out.out.out.name;
      nested = refuses (idOf realDerivation);
      inAList = refuses (idOf [ realDerivation ]);
      deep = refuses (idOf {
        a = {
          b = realDerivation;
        };
      });
      # CONTROL: a clean value still mints in the same run, so the refusals are the gate's and not
      # the whole cell falling over.
      controlCleanValueStillMints = admits (idOf {
        a = 1;
      });
    };
    expected = {
      controlFixtureIsADerivation = true;
      controlFixtureIsSelfReferential = true;
      nested = true;
      inAList = true;
      deep = true;
      controlCleanValueStillMints = true;
    };
  };

  ## The worked example — the preimage a reader can check by hand.

  # The caller supplies `[ "user" "host" ]` and the preimage comes out `host` before `user`: the
  # sort happened inside the attrset, not in the caller. The relatum values carry colons and are
  # unaffected — the colon refusal constrains the KIND only.
  #
  # Every node carries its type tag: the pairs frame renders `{`…`}`, each key is JSON-quoted and
  # colon-terminated, and each string VALUE is tagged `s` before its own JSON rendering. The
  # preimage moved when the encoder stopped delegating structure to `toJSON`, which ADR-0016's
  # "internal addressing only — nothing durable may depend on it" clause is what makes admissible.
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
    expected = "owns:" + builtins.hashString "sha256" ''{"host":s"sha256:bbb","user":s"sha256:aaa",}'';
  };

  # ★ THE MINT'S OWN OUTER FRAME IS NOT CALLER DATA, and this cell pins the consequence. The pairs
  # record is synthesized by the mint, so the derivation gate does not apply to it: a kind carrying
  # an ordinary `type` option whose value happens to be the string "derivation" mints normally.
  # Routing the frame back through the walk would refuse it an identity it is entitled to.
  # CONTROL, in the same cell: a caller VALUE of that shape is still refused, so the gate is shown
  # to be alive rather than removed.
  flake.tests.identity-encoding.test-outer-frame-is-not-caller-data = {
    expr = {
      typeLabelMints = admits (hashIdentity "k" [ "type" ] (_: "derivation"));
      derivationValueStillRefused = refuses (idOf drvShaped);
    };
    expected = {
      typeLabelMints = true;
      derivationValueStillRefused = true;
    };
  };
}
