# A function module is open content (den-hoag-egei0): the plane cannot see into its body, so `modules`
# compares it by a subject each construction allocates (den-hoag-a7c9r). Two constructions holding the
# same function decide by NO closure identity, so every route that reaches one function refuses on all
# three evaluators. Before, `==` over the function decided: value-slot identity on Nix and Determinate,
# closure identity on Lix, so the shared, `import`ed, selected and module-argument routes read `true` on
# Lix alone. A path module compares as itself, and so does a functor attrset (its attributes' slots
# travel through `import`, selection and `//`); one construction with itself is one value. Each row reads
# `[ marksEqual kindEq ]` over two constructions in two schemas, on both entry arms.
{
  lib,
  genSchema,
  genMerge,
  ...
}:
let
  T = genMerge.types;
  opt = t: genMerge.mkOption { type = t; };
  arms = {
    default = { };
    mkType = {
      mkType =
        { defs, ... }:
        {
          __functor =
            _:
            { ... }:
            {
              imports = map (d: d.value) defs;
            };
        };
    };
  };
  dec =
    a: b:
    let
      r = builtins.tryEval (builtins.deepSeq (genSchema.kindEq a b) (genSchema.kindEq a b));
    in
    if r.success then r.value else "REFUSED";
  read = a: b: [
    (a.__mint.minted == b.__mint.minted)
    (dec a b)
  ];
  lam = { ... }: { options.f = opt T.str; };
  fnFile = builtins.toFile "fm-fn.nix" ''{ ... }: { options.f = { _type = "option"; }; }'';
  pathMod = builtins.toFile "fm-path.nix" ''{ options.f = { _type = "option"; }; }'';
  fnctFile = builtins.toFile "fm-functor.nix" ''{ __functor = _: { ... }: { options.f = { _type = "option"; }; }; }'';
  holder = {
    m = lam;
  };
  A = {
    options.x = opt T.str;
  };
  rowsOf =
    args:
    let
      schemaOf =
        kinds:
        (genMerge.evalModuleTree { } [
          { options.schema = genSchema.mkSchemaOption args; }
          { config.schema = kinds; }
        ]).config.schema;
      pl =
        m:
        (schemaOf {
          a = A // {
            imports = [ m ];
          };
        }).a;
      pd =
        m:
        (schemaOf {
          a = A // {
            imports = [ m ];
          };
          b = {
            options.y = opt T.str;
            inherits = [ "a" ];
          };
        }).b;
      viaArg =
        (genMerge.evalModuleTree { } [
          { options.schema = genSchema.mkSchemaOption args; }
          { _module.args.m = lam; }
          ({ m, ... }: {
            config.schema.a = A // {
              imports = [ m ];
            };
          })
        ]).config.schema.a;
      one = pl lam;
    in
    {
      shared = read (pl lam) (pl lam);
      parentShared = read (pd lam) (pd lam);
      importEach = read (pl (import fnFile)) (pl (import fnFile));
      selectEach = read (pl holder.m) (pl holder.m);
      moduleArgument = read viaArg (
        (genMerge.evalModuleTree { } [
          { options.schema = genSchema.mkSchemaOption args; }
          { _module.args.m = lam; }
          ({ m, ... }: {
            config.schema.a = A // {
              imports = [ m ];
            };
          })
        ]).config.schema.a
      );
      pathShared = read (pl pathMod) (pl pathMod);
      functorEach = read (pl (import fnctFile)) (pl (import fnctFile));
      self = read one one;
    };
  refused = [
    true
    "REFUSED"
  ];
  same = [
    true
    true
  ];
  expected = {
    shared = refused;
    parentShared = refused;
    importEach = refused;
    selectEach = refused;
    moduleArgument = refused;
    pathShared = same;
    functorEach = same;
    self = same;
  };
in
{
  flake.tests.kind-function-module-subject = builtins.listToAttrs (
    builtins.concatLists (
      lib.mapAttrsToList (
        arm: args:
        lib.mapAttrsToList (row: v: {
          name = "test-${arm}-${row}";
          value = {
            expr = v;
            expected = expected.${row};
          };
        }) (rowsOf args)
      ) arms
    )
  );
}
