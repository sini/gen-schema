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
    # The option's type is its entry type's construction only while the two constructors accept one
    # formal set. Before P1 (den-hoag-7gp66) that was a runtime `builtins.functionArgs` comparison;
    # both doors are now bare `args:` lambdas (P1's catchable-refusal door shape), so `functionArgs`
    # reads `{}` for both and the comparison would hold vacuously rather than state anything.
    # Retargeted to the behavior the invariant is FOR: both doors admit the identical known field set,
    # and both refuse an identical fresh unknown one ("bogus", this library's own not-a-field probe).
    test-option-formals-are-the-entry-formals = {
      expr =
        let
          knownArgs = {
            baseModule = null;
            collections = { };
            computed = null;
            mixins = [ ];
            mkType = null;
            strict = true;
            keySemantics = { };
            specialArgs = { };
          };
          admits = f: (builtins.tryEval (builtins.seq (f knownArgs) true)).success;
          refusesUnknown =
            f: !(builtins.tryEval (builtins.seq (f (knownArgs // { bogus = 1; })) true)).success;
        in
        {
          bothAdmitKnown = admits mkSchemaOption && admits mkSchemaEntryType;
          bothRefuseUnknown = refusesUnknown mkSchemaOption && refusesUnknown mkSchemaEntryType;
        };
      expected = {
        bothAdmitKnown = true;
        bothRefuseUnknown = true;
      };
    };
  };
}
