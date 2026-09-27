# THE CLOSED-DOOR TABLE (den-hoag-7gp66 P1) — one row per closed door gen-schema publishes, read by
# `ci/tests/door-checks.nix` (catchability) and `ci/tests-error.nix` (the refusal bytes). It lives
# outside ./tests so the harness does not collect it as a test module.
#
# A row is the door's name as its refusal spells it, its required fields, its options (`[ ]` for a
# RECORD door, R5: open, an extra field admitted; non-empty for an OPTIONS or a MIXED door, closed
# until P2), a VALID record, and `call`, which applies the door to a record as far as the door's own
# check runs. `call valid` must answer: that is each row's live control, so a refusal below is the
# check firing and not a broken fixture.
#
# SIX DOORS. `identityKeysForKind` is curried past its check: `call` applies only the FIRST argument
# (never the `kindValue` that follows), because that is where the door's own `checkOptions` runs
# (§v1.9 cell 1' of the spec).
{
  genSchema,
  genMerge,
}:
{
  mkFieldValidator = {
    required = [
      "fields"
      "name"
      "check"
      "message"
    ];
    options = [ ];
    valid = {
      fields = [ "port" ];
      name = "has-port";
      check = inst: inst ? port;
      message = "must have a port";
    };
    call = genSchema.mkFieldValidator;
  };

  mkMixin = {
    required = [ "define" ];
    options = [
      "requires"
      "provides"
      "kinds"
      "name"
    ];
    valid = {
      requires = [ "port" ];
      provides = [ "metrics_port" ];
      define = _parent: { metrics_port = 9090; };
    };
    call = genSchema.mkMixin;
  };

  evalSchema = {
    required = [ "modules" ];
    options = [
      "schemaOption"
      "specialArgs"
    ];
    valid = {
      modules = [
        {
          config.schema.host = {
            options.addr = genMerge.mkOption { type = genMerge.types.str; };
          };
        }
      ];
    };
    call = genSchema.evalSchema;
  };

  identityKeysForKind = {
    required = [ ];
    options = [ "specialArgs" ];
    valid = { };
    call = genSchema.identityKeysForKind;
  };

  mkSchemaEntryType = {
    required = [ ];
    options = [
      "baseModule"
      "collections"
      "computed"
      "mixins"
      "mkType"
      "strict"
      "keySemantics"
      "specialArgs"
    ];
    valid = { };
    call = genSchema.mkSchemaEntryType;
  };

  mkSchemaOption = {
    required = [ ];
    options = [
      "baseModule"
      "collections"
      "computed"
      "mixins"
      "mkType"
      "strict"
      "keySemantics"
      "specialArgs"
    ];
    valid = { };
    call = genSchema.mkSchemaOption;
  };
}
