# Base module args reach a KIND'S OWN OPTION TREE — `evalSchema`/`mkSchemaOption`'s `specialArgs`.
#
# ★★★ THE SECOND ARM OF `denful/den#687`, AND `mkInstanceType` IS NOT ON IT. A kind whose module
# forces an argument WHILE DECLARING an option recurses with NO INSTANCE ANYWHERE: the kind tree is
# built by `mkSchemaEntryType`'s own `introspect` (`lib/entry-type.nix`, a direct
# `merge.evalModuleTree`), which a kind reaches long before any instance constructor does. Threading
# the instance side alone leaves this arm diverging, and at a gen-merge carrying ADR-0033's guard it
# surfaces as a named refusal instead — which is a better message and not a fix.
#
# ★★ THE FORCING EXPRESSION IS ITSELF AN INSTRUMENT AND IT HAS A CONTROL HERE, because two obvious
# spellings of "force the kind" are DEAD for this question and both read green:
#   · `<schema>._kindNames` does not force a kind's modules at all;
#   · `attrNames <kind>.options` applies the module but not its option DEFAULTS — a missing formal is
#     a thunk that only detonates when USED, so the key set comes back intact.
# Measured both, one run, against a kind whose default is an unconditional `throw`: neither fired.
# `…-the-forcing-position-is-live-control` is the arm that keeps the cells below honest.
#
# ★ NO `withArgs` HERE. The type-level inlet exists where a `types.submodule` call would otherwise
# have to take its args as a constructor attrset, which `isModuleValue` cannot tell from a module.
# `introspect` calls the engine directly — no type, no ambiguity — so the channel is
# `evalModuleTree`'s own `specialArgs ? { }`, reached by an ordinary named formal. One vocabulary,
# two shapes, each forced by what is in the way at its site.
{
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) evalSchema mkSchemaOption;
  inherit (genMerge) mkOption;

  tagged.inletTag = "PASSED-BY-CALLER";

  # THE SUBJECT: forces its arg while DECLARING, which is the position that recurses.
  fleetModule =
    { argand, ... }:
    {
      options.hostName = mkOption {
        type = genMerge.types.str;
        default = argand.inletTag;
      };
    };

  # A kind needing no arg — the arm that must keep working untouched.
  plainModule = {
    options.hostName = mkOption {
      type = genMerge.types.str;
      default = "plain";
    };
  };

  # An unconditional throw in the SAME position as the subject's default.
  boomModule = {
    options.hostName = mkOption {
      type = genMerge.types.str;
      default = throw "gen-schema-test: the forcing position is live";
    };
  };

  schemaOf =
    args: mod:
    evalSchema (
      {
        modules = [
          {
            config.schema.fleet = {
              imports = [ mod ];
            };
          }
        ];
      }
      // args
    );

  # NOT `attrNames`, NOT `_kindNames` — see the header. This reads the option's default, which is
  # what actually forces the kind module's body.
  defaultOf = s: s.fleet.options.hostName.default;
  survives = e: (builtins.tryEval (builtins.deepSeq e null)).success;
in
{
  flake.tests.schema-special-args = {
    # ── the gating oracle for the uninstantiated arm ────────────────────────────────────────────
    # ★ ON THE VALUE, not on "it evaluated": the option takes what the caller handed in, which is
    # the only reading that separates a working channel from a better error message.
    test-an-uninstantiated-kind-s-option-tree-takes-the-caller-s-arg = {
      expr = defaultOf (
        schemaOf {
          specialArgs = {
            argand = tagged;
          };
        } fleetModule
      );
      expected = "PASSED-BY-CALLER";
    };
    # The same channel stated one constructor down, where a caller who builds the schema option
    # themselves reaches it.
    test-mkSchemaOption-threads-its-args-to-the-kind-tree = {
      expr = defaultOf (
        schemaOf {
          schemaOption = mkSchemaOption {
            specialArgs = {
              argand = tagged;
            };
          };
        } fleetModule
      );
      expected = "PASSED-BY-CALLER";
    };
    # LIVE CONTROL: the SAME kind with no args is refused — catchably, and not by diverging.
    test-the-same-kind-without-special-args-is-refused-control = {
      expr = survives (defaultOf (schemaOf { } fleetModule));
      expected = false;
    };
    # ★★ LIVE CONTROL ON THE INSTRUMENT ITSELF: an unconditional throw in the position the cells
    # above read MUST fire. Without it, all three are consistent with a read that forces nothing —
    # which is exactly how the two dead spellings named in the header pass.
    test-the-forcing-position-is-live-control = {
      expr = survives (defaultOf (schemaOf { } boomModule));
      expected = false;
    };
    # LIVE CONTROL: a kind declaring no extra formal is untouched by the thread.
    test-a-kind-needing-no-arg-is-unaffected-control = {
      expr = defaultOf (
        schemaOf {
          specialArgs = {
            argand = tagged;
          };
        } plainModule
      );
      expected = "plain";
    };
    # LIVE CONTROL for the refusal added beside this channel: a caller-supplied `schemaOption` with
    # no `specialArgs` is the ordinary case and still evaluates.
    test-a-supplied-schemaOption-without-args-still-evaluates-control = {
      expr = defaultOf (schemaOf { schemaOption = mkSchemaOption { }; } plainModule);
      expected = "plain";
    };
  };
}
