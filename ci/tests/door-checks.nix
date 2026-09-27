# THE CLOSED-DOOR CHECKS (den-hoag-7gp66 P1) — every published closed door catches its own
# violations.
#
# A native closed formal (`{ define }:`) aborts UNCATCHABLY on an unknown or a missing argument —
# not even `builtins.tryEval` sees it, which is ADR-0025 item 1's named defect. Each door in
# `../doors.nix` now takes a bare formal and applies gen-prelude's shared `checkRequired` (RECORD
# doors), `checkOptions` (OPTIONS doors) or `checkOptions` over `checkRequired` (MIXED doors), so
# the same violations are NAMED and CATCHABLE. Per row, generated:
#   - valid call answers                 (the row's live control)
#   - missing required field refused     (every door with a non-empty `required`)
#   - extra field admitted               (RECORD doors — R5's stated price)
#   - unknown option refused             (OPTIONS and MIXED doors — closed until P2)
#   - non-attrset argument refused       (the check primitive's own refusal)
#
# `success == false` pins catchability, not the message; WHICH refusal fired, and that it names the
# door (R6), is pinned byte-for-byte in `ci/tests-error.nix`'s `door-checks` group.
{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  doors = import ../doors.nix { inherit genSchema genMerge; };

  # WHNF of the application: every door asserts its check where its record is applied (or, for a
  # door curried past it, at the first application, where the native formal runs), so WHNF is where
  # the check fired.
  outcome = e: (builtins.tryEval (builtins.seq e null)).success;

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
    );
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
      expected = 6;
    };
  }
  // lib.concatMapAttrs cellsFor doors;
}
