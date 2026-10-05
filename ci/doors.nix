# THE DOOR TABLE (den-hoag-7gp66 P1, then P2) — one row per record-taking step gen-schema publishes,
# read by `ci/tests/door-checks.nix` (catchability) and `ci/tests-error.nix` (the refusal bytes). It
# lives outside ./tests so the harness does not collect it as a test module.
#
# A row is the door's name as its refusal spells it, its required fields, its options, a VALID
# argument, and `call`, the step itself. After P2 every row is one of two kinds:
#   · a RECORD step (`options = [ ]`, R5: open, an extra field admitted): `mkFieldValidator`,
#     `mkValidator` and `schemaFn` (one required record, R7(a) and the keyed-record ruling);
#   · an OPTIONS step (`required = [ ]`, closed, first in the call): every other row. Its operands
#     follow it positionally (`evalSchema opts modules`, `mkInstanceRegistry opts kind`, `mkCodec opts
#     kind`, `mkInstanceType opts kind`, `mkMixin opts define`, `constructionRelation opts name self`,
#     `identityKeysForKind opts kind`), so `call` applies the options step alone, where its check runs.
# `call valid` must answer: that is each row's live control, so a refusal below is the check firing
# and not a broken fixture.

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

  mkValidator = {
    required = [
      "name"
      "pred"
      "message"
    ];
    options = [ ];
    valid = {
      name = "has-port";
      pred = inst: inst ? port;
      message = "must have a port";
    };
    call = genSchema.mkValidator;
  };

  schemaFn = {
    required = [
      "description"
      "type"
      "fn"
    ];
    options = [ ];
    valid = {
      description = "the port";
      type = genMerge.types.int;
      fn = _: 1;
    };
    call = genSchema.schemaFn;
  };

  mkMixin = {
    required = [ ];
    options = [
      "requires"
      "provides"
      "kinds"
      "name"
    ];
    valid = {
      requires = [ "port" ];
      provides = [ "metrics_port" ];
    };
    call = genSchema.mkMixin;
  };

  evalSchema = {
    required = [ ];
    options = [
      "schemaOption"
      "specialArgs"
    ];
    valid = { };
    call = genSchema.evalSchema;
  };

  identityKeysForKind = {
    required = [ ];
    options = [
      "specialArgs"
    ];
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

  mkInstanceType = {
    required = [ ];
    options = [
      "extraModules"
      "strict"
      "specialArgs"
    ];
    valid = { };
    call = genSchema.mkInstanceType;
  };

  mkInstanceRegistry = {
    required = [ ];
    options = [
      "extraModules"
      "refs"
      "refinements"
      "strict"
      "description"
      "derive"
      "deriveEither"
      "specialArgs"
    ];
    valid = { };
    call = genSchema.mkInstanceRegistry;
  };

  mkCodec = {
    required = [ ];
    options = [
      "fields"
      "types"
      "excludeFields"
    ];
    valid = { };
    call = genSchema.mkCodec;
  };

  constructionRelation = {
    required = [ ];
    options = [
      "minted"
      "compared"
    ];
    valid = { };
    call = genSchema.constructionRelation;
  };

  # Not a row: one module list the cells evaluate a kind tree from.
  evalSchemaModules = [
    {
      config.schema.host = {
        options.addr = genMerge.mkOption { type = genMerge.types.str; };
      };
    }
  ];
}
