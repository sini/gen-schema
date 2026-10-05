# THE DOOR CHECKS (den-hoag-7gp66 P1, then P2) — every published record-taking step catches its own
# violations, at its own application, catchably.
#
# A native closed formal (`{ define }:`) aborts UNCATCHABLY on an unknown or a missing argument —
# not even `builtins.tryEval` sees it, which is ADR-0025 item 1's named defect. Each row of
# `../doors.nix` is a `prelude.door` step: a RECORD step (open, R5) or an OPTIONS step (closed, first
# in the call), so the same violations are NAMED and CATCHABLE. Per row, generated:
#   - valid call answers                 (the row's live control)
#   - missing required field refused     (every RECORD step)
#   - extra field admitted               (RECORD steps — R5's stated price)
#   - unknown option refused             (OPTIONS steps)
#   - non-attrset argument refused       (the check primitive's own refusal)
#   - the published contract agrees with the row, as data and through the functor-aware reader (D3)
# and, by hand below, the old one-record shapes refused at their first application, a non-default
# option reaching the result (G3), and a partially applied options step composing.
#
# `success == false` pins catchability, not the message; WHICH refusal fired, and that it names the
# door (R6), is pinned byte-for-byte in `ci/tests-error.nix`'s `door-checks` group.
{
  lib,
  genSchema,
  genMerge,
  prelude,
  ...
}:
let
  table = import ../doors.nix { inherit genSchema genMerge; };
  doors = builtins.removeAttrs table [ "evalSchemaModules" ];
  doors' = table;

  # WHNF of the application: every door asserts its check where its record is applied (or, for a
  # door curried past it, at the first application, where the native formal runs), so WHNF is where
  # the check fired.
  outcome = e: (builtins.tryEval (builtins.seq e null)).success;

  # One kind value, for the steps whose operand is a kind.
  kindValue = (genSchema.evalSchema { } doors'.evalSchemaModules).host;

  cellsFor =
    key: row:
    let
      k = lib.toLower key;
    in
    {
      "test-${k}-valid-call-answers" = {
        expr = outcome (row.call row.valid);
        expected = true;
      };
      "test-${k}-non-attrset-argument-refused-catchably" = {
        expr = outcome (row.call 1);
        expected = false;
      };
    }
    // (
      if row.required == [ ] then
        { }
      else
        {
          "test-${k}-missing-required-field-refused-catchably" = {
            expr = outcome (row.call (builtins.removeAttrs row.valid [ (builtins.head row.required) ]));
            expected = false;
          };
        }
    )
    // (
      if row.options == [ ] then
        {
          "test-${k}-extra-field-on-a-record-is-admitted" = {
            expr = outcome (row.call (row.valid // { bogus = 1; }));
            expected = true;
          };
        }
      else
        {
          "test-${k}-unknown-option-refused-catchably" = {
            expr = outcome (row.call (row.valid // { bogus = 1; }));
            expected = false;
          };
        }
    )
    // {
      "test-${k}-publishes-its-contract" = {
        expr = {
          inherit (row.call.__contract) required optional open;
          args = prelude.functionArgs row.call;
        };
        expected = {
          inherit (row) required;
          optional = row.options;
          open = row.options == [ ];
          args =
            builtins.listToAttrs (map (f: lib.nameValuePair f false) row.required)
            // builtins.listToAttrs (map (f: lib.nameValuePair f true) row.options);
        };
      };
    };
in
{
  flake.tests.door-checks = {
    # ★ LIVE CONTROLS FOR THE WHOLE SUITE: `tryEval` catches an ordinary throw, and a non-throwing
    # value answers. Without these, a broken `outcome` reading one constant satisfies half the cells.
    test-control-tryeval-catches-an-ordinary-throw = {
      expr = outcome (throw "control probe, not this suite's subject");
      expected = false;
    };
    test-control-tryeval-answers-a-non-throwing-value = {
      expr = outcome 1;
      expected = true;
    };
    # The table is the subject; a row dropped from it would drop its cells silently.
    test-door-table-rows = {
      expr = builtins.length (builtins.attrNames doors);
      expected = 12;
    };

    # ── P2: the old one-record shapes are refused at their first application ──
    # A pre-P2 call hands the operands where the options now sit: their names are not options, so
    # the options step refuses them by name before any operand is read.
    test-the-old-one-record-shapes-are-refused-at-the-application = {
      expr = map outcome [
        (genSchema.evalSchema { modules = [ ]; })
        (genSchema.mkMixin { define = _: { }; })
        (genSchema.mkInstanceRegistry kindValue)
        (genSchema.mkInstanceType kindValue)
        (genSchema.mkCodec kindValue)
      ];
      expected = [
        false
        false
        false
        false
        false
      ];
    };
    # The positional record constructors are refused too: a bare string is not the record.
    test-the-old-positional-shapes-are-refused-at-the-application = {
      expr = map outcome [
        (genSchema.mkValidator "has-port")
        (genSchema.schemaFn "the port")
      ];
      expected = [
        false
        false
      ];
    };
    # G3: a non-default option reaches the result (`differ`, against `{ }`), and the partially
    # applied step agrees with the full call (`agree`).
    test-a-non-default-option-reaches-the-result = {
      expr =
        let
          described = genSchema.mkInstanceRegistry { description = "spools"; };
          mixin = genSchema.mkMixin { name = "metrics"; };
        in
        {
          registry = {
            agree =
              (described kindValue).description
              == (genSchema.mkInstanceRegistry { description = "spools"; } kindValue).description;
            differ =
              (described kindValue).description != (genSchema.mkInstanceRegistry { } kindValue).description;
          };
          mixin = {
            agree = (mixin (_: { })).name == (genSchema.mkMixin { name = "metrics"; } (_: { })).name;
            differ = (mixin (_: { })).name != (genSchema.mkMixin { } (_: { })).name;
          };
        };
      expected = {
        registry = {
          agree = true;
          differ = true;
        };
        mixin = {
          agree = true;
          differ = true;
        };
      };
    };
    # Composition: `evalSchema opts` is a value mapped over module lists.
    test-a-partially-applied-evalSchema-maps-over-module-lists = {
      expr = map (s: s._kindNames) (
        map (genSchema.evalSchema { }) [
          doors'.evalSchemaModules
          [ ]
        ]
      );
      expected = [
        [ "host" ]
        [ ]
      ];
    };
  }
  // lib.concatMapAttrs cellsFor doors;
}
