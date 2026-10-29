# One kind declaration (`host`, one function, one source position) evaluated under two schemas: one
# keeping `collections.excludes` in identity (`"guarded"`, the kind defines it) and one declaring it
# `identity = false` (`"plain"`). The declaration witness does not hash the schema's collections, so
# the two constructions meet at one node. The outer tree's registry reaches the inner tree's `host`
# `copies` times through `extraModules`: one construction reached repeatedly beside the outer's own.
# `read = "instance"`: the collection reads the instance under construction (minting it would recurse);
# `"const"`: it does not. The value is the instance's address, read without `tryEval`.
{
  genSchema,
  genMerge,
  outer,
  inner,
  copies,
  self,
  read,
}:
let
  S = genSchema;
  T = genMerge.types;
  excludes =
    g:
    {
      default = [ ];
      merge = acc: val: acc ++ val;
    }
    // (if g == "guarded" then { } else { identity = false; });
  sameTree =
    g: extra:
    genMerge.evalModuleTree { } [
      (
        { config, ... }:
        {
          options.schema = S.mkSchemaOption { collections.excludes = excludes g; };
          options.hosts = S.mkInstanceRegistry { extraModules = extra; } config.schema.host;
          options.aspects = genMerge.mkOption { type = T.attrsOf T.anything; };
          config.schema.conf = { };
          config.schema.host = {
            inherits = if self == "parented" then [ config.schema.conf ] else [ ];
            options.addr = genMerge.mkOption { type = T.str; };
            excludes = [ config.aspects.unwanted ];
          };
          config.hosts.igloo.addr = "10.0.1.1";
          config.aspects.unwanted.domain = if read == "instance" then config.hosts.igloo.addr else "const";
        }
      )
    ];
  innerKind = (sameTree inner [ ]).config.schema.host;
in
(sameTree outer (builtins.genList (_: innerKind) copies)).config.hosts.igloo.addr
