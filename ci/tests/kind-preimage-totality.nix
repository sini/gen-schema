# A parented kind's mark is TOTAL where its own module reads its parent (den-hoag-a7c9r U2, gate v0 CF1).
#
# A parent enters its child's plane by its own mark, and the child tags only what no parent publishes.
# The own plane is read off the published tree, with the parents present, so a child module that reads
# a parent's option declaration or config still evaluates. An own plane evaluated without the parents
# aborts these with `attribute 'x' missing` / `attribute 'flag' missing`, which `tryEval` cannot catch;
# nix-unit reports each cell apart.
#
# Every cell reads both entry arms: `mkSchemaOption { }` and a functor `mkType` composing its defs.
# Unmoved guards, which an own plane without the parents also passes: `aliasParent`, `probesOptions`
# and `readsConfigMark` (the `enum config.choices` reader). The cells that discriminate are
# `readsOptionType` (the gate's `readsOptionsMark`), `configType` and the instance `id_hash`.
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
  schemaOf =
    args: kinds:
    (genMerge.evalModuleTree { } [
      { options.schema = genSchema.mkSchemaOption args; }
      { config.schema = kinds; }
    ]).config.schema;
  A = {
    options.x = opt T.str;
    options.flag = genMerge.mkOption {
      type = T.bool;
      default = true;
    };
    options.choices = genMerge.mkOption {
      type = T.listOf T.str;
      default = [
        "p"
        "q"
      ];
    };
  };
  # the child's mark and its published option names
  child =
    args: m:
    let
      b =
        (schemaOf args {
          a = A;
          b = {
            inherits = [ "a" ];
            imports = [ m ];
          };
        }).b;
    in
    [
      (builtins.isString b.__mint.minted)
      (builtins.attrNames b.options)
    ];
  cases = args: {
    readsOptionType = child args ({ options, ... }: { options.y = opt options.x.type; });
    configType = child args (
      { config, ... }:
      {
        options.y = opt (if config.flag then T.str else T.int);
      }
    );
    aliasParent = child args (lib.mkAliasOptionModule [ "y" ] [ "x" ]);
    probesOptions = child args (
      { options, ... }:
      {
        options.y = opt (if options ? x then T.str else T.int);
      }
    );
    readsConfigMark = child args ({ config, ... }: { options.y = opt (T.enum config.choices); });
  };
  published = [
    true
    [
      "choices"
      "flag"
      "x"
      "y"
    ]
  ];
  # an instance of a parented kind whose own module reads its parent's option declaration: its
  # `id_hash` is a value
  idHash =
    (genMerge.evalModuleTree { } [
      (
        { config, ... }:
        {
          options.schema = genSchema.mkSchemaOption { };
          options.bs = genSchema.mkInstanceRegistry { } config.schema.b;
          config.schema.a.options.x = opt T.str;
          config.schema.b = {
            inherits = [ "a" ];
            imports = [ ({ options, ... }: { options.y = opt options.x.type; }) ];
          };
          config.bs.i1 = {
            x = "u";
            y = "v";
          };
        }
      )
    ]).config.bs.i1;
in
{
  flake.tests.kind-preimage-totality =
    builtins.listToAttrs (
      builtins.concatLists (
        lib.mapAttrsToList (
          arm: args:
          lib.mapAttrsToList (case: v: {
            name = "test-${arm}-${case}";
            value = {
              expr = v;
              expected = published;
            };
          }) (cases args)
        ) arms
      )
    )
    // {
      test-instance-id-hash-is-a-value = {
        expr = [
          idHash.y
          (builtins.isString idHash.id_hash)
        ];
        expected = [
          "v"
          true
        ];
      };
    };
}
