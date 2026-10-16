# den-hoag-9zyp7: the trees `collection-in-identity` (./tests) and `collection-in-identity-refusals`
# (./tests-error.nix) read. A kind keeps a collection in its identity (undeclared) whose contents
# read an instance the kind types, den#719's shape: the instance's import reads the content stamp
# only, so every read serves; a `//` copy of a kind's identity cells is refused where an identity
# is answered, and a content copy where the instance is imported.
{
  genSchema,
  genMerge,
  genAlgebra,
}:
let
  inherit (genSchema) mkSchemaOption mkInstanceRegistry;
  str = genMerge.types.str;
  excludes = {
    default = [ ];
    merge = acc: val: acc ++ val;
  };
  # `plain`: the collection's contents read the instance's `addr`; `selfId`: its `id_hash`.
  shapeTree =
    shape:
    (genMerge.evalModuleTree { } [
      (
        { config, ... }:
        {
          options.schema = mkSchemaOption { collections.excludes = excludes; };
          options.hosts = mkInstanceRegistry { } config.schema.host;
          options.aspects = genMerge.mkOption { type = genMerge.types.attrsOf genMerge.types.anything; };
          config.schema.host = {
            options.addr = genMerge.mkOption { type = str; };
            excludes = [ config.aspects.unwanted ];
          };
          config.hosts.igloo.addr = "10.0.1.1";
          config.aspects.unwanted.domain =
            if shape == "selfId" then config.hosts.igloo.id_hash else config.hosts.igloo.addr;
        }
      )
    ]).config;
  copyOf =
    mode: k:
    k
    // {
      mint.__mint.minted = "forged";
      sealed.__sealed = { };
      content.strict = !k.strict;
      none = { };
    }
    .${mode};
  # The schemas a copy is taken on: `U` seals nothing; `UC` seals `computed`; `GC` keeps a collection
  # of data in the identity beside `computed`; `GP` is the plain shape.
  schemas = {
    U = { };
    UC.computed = _: _: { c = 1; };
    GC = {
      collections.excludes = excludes;
      computed = _: _: { c = 1; };
    };
  };
  # The registry is handed `copyOf mode` of the schema's kind.
  copyTree =
    s: mode:
    (genMerge.evalModuleTree { } [
      (
        { config, ... }:
        if s == "GP" then
          {
            options.schema = mkSchemaOption { collections.excludes = excludes; };
            options.hosts = mkInstanceRegistry { } (copyOf mode config.schema.host);
            options.aspects = genMerge.mkOption { type = genMerge.types.attrsOf genMerge.types.anything; };
            config.schema.host = {
              options.addr = genMerge.mkOption { type = str; };
              excludes = [ config.aspects.unwanted ];
            };
            config.hosts.igloo.addr = "10.0.1.1";
            config.aspects.unwanted.domain = config.hosts.igloo.addr;
          }
        else
          {
            options.schema = mkSchemaOption schemas.${s};
            options.hosts = mkInstanceRegistry { } (copyOf mode config.schema.host);
            config.schema.host = {
              options.addr = genMerge.mkOption { type = str; };
            }
            // (if s == "GC" then { excludes = [ "x" ]; } else { });
            config.hosts.igloo.addr = "10.0.1.1";
          }
      )
    ]).config;
  # A child naming its parent BY VALUE, the value a copy (`formOf`'s foreign-value door).
  childOf =
    mode:
    (genMerge.evalModuleTree { } [
      (
        { config, ... }:
        {
          options.schema = mkSchemaOption { computed = _: _: { c = 1; }; };
          config.schema.par.options.r = genMerge.mkOption {
            type = str;
            default = "r";
          };
          config.schema.kid = {
            inherits = [ (copyOf mode config.schema.par) ];
            options.addr = genMerge.mkOption { type = str; };
          };
        }
      )
    ]).config.schema.kid;
  # A `computed` field partial on the projection (`tags` declared out of the identity).
  partialTree =
    (genMerge.evalModuleTree { } [
      (
        { config, ... }:
        {
          options.schema = mkSchemaOption {
            collections.tags = excludes // {
              identity = false;
            };
            computed = c: _: { f = builtins.head c.tags; };
          };
          options.nodes = mkInstanceRegistry { } config.schema.node;
          config.schema.node = {
            options.addr = genMerge.mkOption { type = str; };
            tags = [ "x" ];
          };
          config.nodes.n1.addr = "a1";
        }
      )
    ]).config;
  # `identityHashForKind` handed the copy, and the instance the copy built (`own`) or the honest one.
  recompute =
    s: mode: inst:
    genSchema.identityHashForKind (copyOf mode (copyTree s "none").schema.host)
      (copyTree s (if inst == "own" then mode else "none")).hosts.igloo;
in
{
  inherit
    shapeTree
    copyTree
    childOf
    partialTree
    recompute
    ;
  identityOf = genAlgebra.identityOf;
}
