# The stamp carries the KIND'S MINTED IDENTITY, not its name.
#
# Two kinds that share the name `host` and differ by a non-key option are two declarations:
# `kindEq` calls them distinct. With the name as the only kind input to the preimage, their
# instances minted ONE `id_hash` whenever the key values were equal, and every identity comparison
# downstream took them for one entity. The cells below pin the split, and the four live arms show
# that the split is the only thing that moved: nothing distinct merged, and nothing equal split.
{
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) evalSchema mkInstanceRegistry identityHashForKind;
  str = genMerge.types.str;

  # A: `host { addr }`. B: `host { addr; tags }`: `tags` is not primitive, so the KEY SETS are equal
  # and only the declaration separates the two kinds.
  kindA =
    (evalSchema {
      modules = [ { config.schema.host.options.addr = genMerge.mkOption { type = str; }; } ];
    }).host;
  kindB =
    (evalSchema {
      modules = [
        {
          config.schema.host.options = {
            addr = genMerge.mkOption { type = str; };
            tags = genMerge.mkOption {
              type = genMerge.types.listOf str;
              default = [ ];
            };
          };
        }
      ];
    }).host;
  # An independently evaluated twin of A: one declaration, one mark.
  kindTwin =
    (evalSchema {
      modules = [ { config.schema.host.options.addr = genMerge.mkOption { type = str; }; } ];
    }).host;
  # A's declaration under another name.
  kindOther =
    (evalSchema {
      modules = [ { config.schema.box.options.addr = genMerge.mkOption { type = str; }; } ];
    }).box;

  inst =
    kindValue: addr:
    (genMerge.evalModuleTree {
      modules = [
        {
          options.reg = mkInstanceRegistry kindValue { };
          config.reg.pewter.addr = addr;
        }
      ];
    }).config.reg.pewter;

  a = inst kindA "10.0.0.1";
  b = inst kindB "10.0.0.1";
in
{
  flake.tests.identity-kind-component = {
    # C5. Same name, different declarations, equal keys and values: two identities.
    test-same-name-different-kinds-mint-two-identities = {
      expr = {
        kindEq = genSchema.kindEq kindA kindB;
        keySetsEqual = a._identityKeys == b._identityKeys;
        stampsEqual = a.id_hash == b.id_hash;
      };
      expected = {
        kindEq = false;
        keySetsEqual = true;
        stampsEqual = false;
      };
    };
    # The live arms: a moved value splits, a different name splits, an independently evaluated
    # twin kind is ONE identity, and the recompute equals the stamp.
    test-control-the-split-is-the-only-move = {
      expr = {
        movedValueSplits = a.id_hash != (inst kindA "10.0.0.2").id_hash;
        otherNameSplits = a.id_hash != (inst kindOther "10.0.0.1").id_hash;
        twinKindIsOneIdentity = a.id_hash == (inst kindTwin "10.0.0.1").id_hash;
        recomputeIsTheStamp = identityHashForKind kindA a == a.id_hash;
        tagIsTheName = builtins.substring 0 5 b.id_hash;
      };
      expected = {
        movedValueSplits = true;
        otherNameSplits = true;
        twinKindIsOneIdentity = true;
        recomputeIsTheStamp = true;
        tagIsTheName = "host:";
      };
    };
  };
}
