# den-hoag-3x3bi (ADR-0025). The `mkType` arm never wrote the let-bound `kind` onto the kind
# value, although the arm's own comment already called it authoritative and `kindResultKeys`
# already annotated it "both branches". A result carrying no `kind` made `.kind` abort
# UNCATCHABLY (`attribute 'kind' missing`, not a `throw` `tryEval` can catch — den-hoag-ciu4r F1)
# and `mkInstanceType` refuse with the FALSE reason "no mark"; a result echoing a WRONG name
# published that name while the mark stayed keyed to the option path. These cells pin the
# kind-value SHAPE these two failures broke: `kind` on a `mkType`-built kind value equals the
# option path, always, regardless of what the `mkType` result carries under that name.
{
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) mkSchemaOption mkInstanceType;

  roleOpt = genMerge.mkOption {
    type = genMerge.types.str;
    default = "x";
  };
  functorOf =
    extra:
    {
      __functor = _: _: {
        options.role = roleOpt;
      };
    }
    // extra;

  # No `kind` at all on the `mkType` result — the defect's first arm.
  mkTypeNoKind = { ... }: functorOf { };
  # Echoes a NAME THAT DISAGREES with the option path it will be merged under.
  mkTypeWrongEcho = { ... }: functorOf { kind = "guest"; };
  # Echoes the CORRECT name — the arm's control: unaffected by the fix either way.
  mkTypeRightEcho = { kind, ... }: functorOf { inherit kind; };

  kindOf =
    mkType: name:
    (genMerge.evalModuleTree {
      modules = [
        { options.schema = mkSchemaOption { inherit mkType; }; }
        { config.schema.${name} = { }; }
      ];
    }).config.schema.${name};

  # The default arm's own control: it never had this defect (`prelude.last loc` is inherited
  # directly on that branch), so it must read exactly as it did before F1.
  defaultKind =
    (genMerge.evalModuleTree {
      modules = [
        { options.schema = mkSchemaOption { }; }
        { config.schema.host = { }; }
      ];
    }).config.schema.host;
in
{
  # F1, arm 1: a `mkType` result carrying no `kind` at all. Before the fix `.kind` aborted
  # uncatchably (a `tryEval` around it does not read as `{ success = false; }` — the abort takes
  # the whole evaluation down, so THIS is the value cell that would have failed to evaluate at
  # all rather than merely mismatch). After the fix it reads the option path.
  flake.tests.mktype-kind-value.test-mktype-arm-writes-kind-with-no-echo = {
    expr = (kindOf mkTypeNoKind "host").kind;
    expected = "host";
  };

  # F1, arm 1 continued: `mkInstanceType` reads `isSchemaKind` (`v ? kind && …`) before it ever
  # reaches the mark, so the no-`kind` kind value refused with the FALSE reason "no mark" even
  # though `__mint.minted` was present and correct. Admission, not the mark, is what this pins.
  flake.tests.mktype-kind-value.test-mktype-arm-with-no-kind-echo-is-admitted-by-mkInstanceType = {
    expr =
      (builtins.tryEval (builtins.deepSeq (mkInstanceType (kindOf mkTypeNoKind "host") { }) true))
      .success;
    expected = true;
  };

  # F1, arm 2: a `mkType` result echoing the WRONG name published that name silently. The
  # let-bound `kind` — the option path — must win.
  flake.tests.mktype-kind-value.test-mktype-arm-kind-overrides-a-wrong-echo = {
    expr = (kindOf mkTypeWrongEcho "host").kind;
    expected = "host";
  };

  # Control: a `mkType` result echoing the RIGHT name. This arm never read wrong before the fix —
  # it is what makes the only live consumer (gen-aspects) latent rather than broken — and must
  # read the same after it.
  flake.tests.mktype-kind-value.test-mktype-arm-kind-matches-a-correct-echo-control = {
    expr = (kindOf mkTypeRightEcho "host").kind;
    expected = "host";
  };

  # Control: the default (non-`mkType`) arm never had this defect; unaffected by the fix.
  flake.tests.mktype-kind-value.test-default-arm-kind-is-unaffected-control = {
    expr = defaultKind.kind;
    expected = "host";
  };
}
