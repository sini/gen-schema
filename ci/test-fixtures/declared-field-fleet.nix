# den-hoag-ien5k T3 — a fleet of `n` nodes of one invented kind (`spindle`), each a member of `loom`, with a
# PLANT at the last node or on the kind, the registry or the schema. Read by `ci/tests/declared-field.nix`
# (the agreement razor). `rows.<node>` is the reader's answer `s` (`declaredField`) and the module-system
# read `m` (`config.spindles.<node>.aspects`), each deep under `tryEval`.
{
  genMerge,
  genSchema,
  plant ? null,
  n ? 4,
}:
let
  inherit (genMerge)
    mkOption
    types
    mkDefault
    mkForce
    mkIf
    mkMerge
    ;
  name = i: "s${toString i}";
  last = name (n - 1);
  is = p: plant == p;
  aspectsDecl = mkOption (
    {
      type = types.listOf (
        if is "enum" then
          types.enum [
            "loom"
            "spare"
          ]
        else
          types.str
      );
      default = [ ];
    }
    // (if is "apply" then { apply = x: x ++ [ "spare" ]; } else { })
  );
  kindConfig =
    if is "kindcfg" then
      { aspects = [ "spare" ]; }
    else if is "kinddefault" || is "kinddefaultnodeforce" || is "samedefault" then
      { aspects = mkDefault [ "spare" ]; }
    else if is "kindmkif" then
      { aspects = mkIf true [ "spare" ]; }
    else if is "kindforce" then
      { aspects = mkForce [ "spare" ]; }
    else
      { };
  schemaOption =
    if is "mixin" then
      genSchema.mkSchemaOption {
        mixins = [
          (genSchema.mkMixin
            {
              requires = [ ];
              provides = [ "extra" ];
            }
            (_: {
              extra = mkOption {
                type = types.int;
                default = 0;
              };
            })
          )
        ];
        baseModule = {
          aspects = aspectsDecl;
          idx = mkOption { type = types.int; };
        };
      }
    else if is "mktype" then
      genSchema.mkSchemaOption {
        mkType =
          { ... }:
          {
            __functor = _: _: {
              options.aspects = aspectsDecl;
              options.idx = mkOption { type = types.int; };
            };
          };
      }
    else
      genSchema.mkSchemaOption { };
  schema = genSchema.evalSchema { inherit schemaOption; } [
    (
      if is "parent" then
        {
          config.schema.fabric = {
            options.aspects = aspectsDecl;
            config.aspects = [ "spare" ];
          };
        }
      else
        { }
    )
    {
      config.schema.spindle =
        if is "mixin" || is "mktype" then
          { }
        else
          {
            ${if is "parent" then "inherits" else null} = [ "fabric" ];
            options.${if is "parent" then null else "aspects"} = aspectsDecl;
            options.idx = mkOption { type = types.int; };
            config = kindConfig;
            ${if is "funmodule" then "imports" else null} = [ ({ ... }: { config.aspects = [ "spare" ]; }) ];
            ${if is "validator" then "validators" else null} = [
              (genSchema.mkValidator {
                name = "any";
                pred = _: true;
                message = "never";
              })
            ];
          };
    }
  ];
  nodeOf =
    i:
    let
      at = name i == last;
      base = {
        aspects = if is "enum" && at then [ "bogus" ] else [ "loom" ];
        idx = i;
      };
      own =
        if !at then
          base
        else if is "omit" then
          removeAttrs base [ "aspects" ]
        else if is "force" then
          base
          // {
            aspects = mkForce [
              "loom"
              "spare"
            ];
          }
        else if is "undeclared" then
          base // { bogusKey = 1; }
        else if is "extradecl" then
          base // { loomCount = 1; }
        else if is "ownname" then
          base // { name = last; }
        else if is "nodemkif" then
          base // { aspects = mkIf true [ "loom" ]; }
        else if is "kinddefaultnodeforce" then
          base // { aspects = mkForce [ "loom" ]; }
        else if is "samedefault" then
          base // { aspects = mkDefault [ "loom" ]; }
        else
          base;
    in
    if at && is "structured" then
      { config = own; }
    else if at && is "structextra" then
      {
        config = own;
        bogusTop = 1;
      }
    else
      own;
  nodes = builtins.listToAttrs (
    builtins.genList (i: {
      name = name i;
      value = nodeOf i;
    }) n
  );
  registryOpts =
    (if is "extramod" then { extraModules = [ { config.aspects = [ "spare" ]; } ]; } else { })
    # C7: an extra module declaring a key the last node sets, and one redeclaring the field
    // (
      if is "extradecl" then
        {
          extraModules = [
            {
              options.loomCount = mkOption {
                type = types.int;
                default = 0;
              };
            }
          ];
        }
      else if is "extraredecl" then
        { extraModules = [ { options.aspects = mkOption { apply = x: x ++ [ "spare" ]; }; } ]; }
      else
        { }
    )
    // (
      if is "derive" then
        { derive = instances: builtins.mapAttrs (_: _: { aspects = [ "spare" ]; }) instances; }
      else
        { }
    )
    // (
      if is "refinement" then
        {
          refinements.aspects = [
            {
              check = v: v != [ ];
              message = "nonempty";
            }
          ];
        }
      else
        { }
    )
    // (
      if is "reffield" then
        {
          extraModules = [
            (
              { ... }:
              {
                options.frame = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                };
              }
            )
          ];
        }
      else
        { }
    );
  modules = [
    {
      options.spindles = genSchema.mkInstanceRegistry registryOpts schema.spindle;
      config.spindles = if is "view" then mkMerge [ nodes ] else nodes;
    }
  ]
  ++ (if is "twodefs" then [ { config.spindles.${last}.aspects = [ "spare" ]; } ] else [ ])
  # C1: the registry option redeclared beside an `attrsOf submodule` whose module defines the field
  ++ (
    if is "redecl" then
      [
        {
          options.spindles = mkOption {
            type = types.attrsOf (types.submodule { config.aspects = [ "k" ]; });
          };
        }
      ]
    else
      [ ]
  );
  ev = genMerge.evalModuleTree { } modules;
  syn = genSchema.declaredField ev.options.spindles "aspects";
  safe =
    x:
    let
      r = builtins.tryEval (builtins.deepSeq x x);
    in
    if r.success then r.value else "<refused>";
  names = builtins.genList name n;
  rows = builtins.listToAttrs (
    map (nm: {
      name = nm;
      value = {
        s = safe (syn nm);
        m = safe ev.config.spindles.${nm}.aspects;
      };
    }) names
  );
in
{
  inherit rows;
  fellBack = builtins.length (builtins.filter (nm: rows.${nm}.s == null) names);
  disagree = builtins.filter (nm: rows.${nm}.s != null && rows.${nm}.s != rows.${nm}.m) names;
}
