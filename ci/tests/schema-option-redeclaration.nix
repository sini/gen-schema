# den-hoag-px98p: a schema option declared twice as ONE construction is one option. Its introspection
# is defined once and reads as it does declared once; two constructions are refused at the option.
# Before it, the type merge unioned the two module sets, the introspection module was imported twice,
# and every read-only introspection field refused "defined 2 times".
#
# Each cell answers a value or REFUSED under tryEval, so the relation is pinned and not a message; the
# declared-once control is the value both redeclarations must equal.
{
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) mkSchemaOption mkSchemaEntryType;
  read =
    decls: field:
    let
      v =
        (genMerge.evalModuleTree { modules = decls ++ [ { config.schema.k = { }; } ]; })
        .config.schema.${field};
      r = builtins.tryEval (builtins.deepSeq v v);
    in
    if r.success then r.value else "REFUSED";
  o = mkSchemaOption { };
  once = [ { options.schema = o; } ];
  oneValue = [
    { options.schema = o; }
    { options.schema = o; }
  ];
  twoCalls = [
    { options.schema = mkSchemaOption { }; }
    { options.schema = mkSchemaOption { }; }
  ];
  differing = [
    { options.schema = mkSchemaOption { strict = true; }; }
    { options.schema = mkSchemaOption { strict = false; }; }
  ];
  typedWrite = [ { config.schema._collectionKeys = [ "fake" ]; } ];
in
{
  flake.tests.schema-option-redeclaration = {
    test-one-construction-reads-as-declared-once = {
      expr = {
        once = read once "_kindNames";
        oneValue = read oneValue "_kindNames";
        twoCalls = read twoCalls "_kindNames";
        oneValueTopology = read oneValue "_topology";
        oneValueCollectionKeys = read oneValue "_collectionKeys" == read once "_collectionKeys";
      };
      expected = {
        once = [ "k" ];
        oneValue = [ "k" ];
        twoCalls = [ "k" ];
        oneValueTopology.k = {
          parent = null;
          children = [ ];
        };
        oneValueCollectionKeys = true;
      };
    };
    test-two-constructions-refuse = {
      expr = {
        kindNames = read differing "_kindNames";
        kinds = read differing "k";
      };
      expected = {
        kindNames = "REFUSED";
        kinds = "REFUSED";
      };
    };
    # `readOnly` is what refuses a well-typed write to a derived output, declared once or twice;
    # with it dropped the write is published as a derived key. The attrset-kind input is a COMPANION,
    # not a discriminator: `listOf str` refuses it whatever `readOnly` says
    # (den-hoag-collectionkeys-collision-oracle-25mae, O6).
    test-introspection-stays-read-only = {
      expr = {
        typedWriteOnce = read (once ++ typedWrite) "_collectionKeys";
        typedWriteTwice = read (oneValue ++ typedWrite) "_collectionKeys";
        kindNamedAfterIntrospection = read (
          once ++ [ { config.schema._collectionKeys = { }; } ]
        ) "_collectionKeys";
      };
      expected = {
        typedWriteOnce = "REFUSED";
        typedWriteTwice = "REFUSED";
        kindNamedAfterIntrospection = "REFUSED";
      };
    };
    # The option's type is its entry type's construction only while the two constructors take one
    # formal set; `mkSchemaOption` refuses by name otherwise, and a planted extra formal reds this.
    test-option-formals-are-the-entry-formals = {
      expr = builtins.functionArgs mkSchemaOption == builtins.functionArgs mkSchemaEntryType;
      expected = true;
    };
  };
}
