# Base module args reach a kind's modules — `mkInstanceType`/`mkInstanceRegistry`'s `specialArgs`.
#
# ★ THE CONSUMER HALF OF gen-merge's TYPE-LEVEL INLET, and the reason it exists. A kind module that
# forces an argument at its OWN WHNF — `{ lib, ... }: { options.x = mkOption { default = lib.foo;
# }; }` — cannot be served from `_module.args`: reading that forces the config fixpoint the module
# is part of, and the result is an UNCATCHABLE infinite recursion naming neither the module nor the
# argument. ADR-0033 rules that declaration-plane read inadmissible; this is the admissible channel
# that replaces it, threaded to `(submodule …).withArgs` inside `mkInstanceType`.
#
# ★ THE REGISTRY ARM IS NOT REDUNDANT. `mkInstanceRegistry` builds its element as
# `attrsOf (mkInstanceType …)`, and a container delegates its rebuild to its ELEMENT's — so the args
# cross a rebuild between the constructor and the instance a consumer actually declares. That arm is
# where a dropped thread would show, and it is the shape every real consumer writes.
{
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema) evalSchema mkInstanceType mkInstanceRegistry;
  inherit (genMerge) mkOption evalModuleTree;

  # A distinguishable value, so the cells read "the arg IS what the caller passed" rather than the
  # weaker "something of that name was in scope".
  tagged = {
    inletTag = "PASSED-BY-CALLER";
    gated = true;
  };

  # The kind's module forces its extra arg while DECLARING an option — the position that recurses
  # when the value can only come from `_module.args`.
  # ★ THE SCHEMA-LEVEL CHANNEL, WHICH IS A DIFFERENT ONE FROM THE INSTANCE CONSTRUCTOR'S BELOW and
  # is fed here because a registry needs it. `mkInstanceRegistry`'s apply pipeline forces
  # `kindValue.refs` unconditionally, and that is `entry-type.nix`'s `introspect` — a kind-tree
  # evaluation with no instance anywhere, served by THIS formal. A kind whose module forces its arg
  # at WHNF is refused there before the identity question is ever reached, so without this the cells
  # below would red for the wrong reason.
  schema = evalSchema {
    specialArgs = {
      site = tagged;
    };
    modules = [
      {
        config.schema.host = {
          imports = [
            (
              { site, ... }:
              {
                options.tag = mkOption {
                  type = genMerge.types.str;
                  default = site.inletTag;
                };
              }
            )
          ];
          options.addr = mkOption { type = genMerge.types.str; };
        };
        # ★ A SECOND KIND, IN A SECOND ARGUMENT POSITION, AND THE IDENTITY CELLS BELOW NEED IT.
        # `host`'s module forces its arg inside an option DEFAULT, so a reader that wants only
        # option NAMES never forces it — which is why a key-set derivation reading names was read as
        # safe and was not. This module forces the arg to produce its OWN WHNF, the
        # `{ lib, ... }: lib.mkIf …` shape a real consumer writes, so APPLYING it forces the arg and
        # every reader of the kind's option set is on that path.
        config.schema.gated = {
          imports = [
            (
              { site, ... }:
              if site.gated then
                {
                  options.gate = mkOption {
                    type = genMerge.types.str;
                    default = "open";
                  };
                }
              else
                { }
            )
          ];
          options.addr = mkOption { type = genMerge.types.str; };
        };
      }
    ];
  };

  viaRegistry = evalModuleTree {
    modules = [
      {
        options.hosts = mkInstanceRegistry schema.host {
          specialArgs = {
            site = tagged;
          };
        };
        config.hosts.igloo.addr = "10.0.1.1";
      }
    ];
  };

  viaType = evalModuleTree {
    modules = [
      {
        options.host = mkOption {
          type = mkInstanceType schema.host {
            specialArgs = {
              site = tagged;
            };
          };
          default = { };
        };
        config.host.addr = "10.0.1.2";
      }
    ];
  };

  # The identity arm's eval, on the kind whose module forces its arg at WHNF. Same thread, same
  # constructors — only the kind differs, so a cell here that moves attributes to the key-set
  # derivation and to nothing else.
  viaGatedRegistry = evalModuleTree {
    modules = [
      {
        options.hosts = mkInstanceRegistry schema.gated {
          specialArgs = {
            site = tagged;
          };
        };
        config.hosts.igloo.addr = "10.0.2.1";
      }
    ];
  };

  viaGatedType = evalModuleTree {
    modules = [
      {
        options.host = mkOption {
          type = mkInstanceType schema.gated {
            specialArgs = {
              site = tagged;
            };
          };
          default = { };
        };
        config.host.addr = "10.0.2.2";
      }
    ];
  };

  # LIVE CONTROL: the same kind, the same declaration, NO `specialArgs`. Without it the two cells
  # above are consistent with the arg arriving from somewhere other than the thread under test.
  withoutArgs = evalModuleTree {
    modules = [
      {
        options.hosts = mkInstanceRegistry schema.host { };
        config.hosts.igloo.addr = "10.0.1.3";
      }
    ];
  };
in
{
  flake.tests.instance-special-args = {
    test-a-registry-threads-its-special-args-to-the-kind-s-modules = {
      expr = viaRegistry.config.hosts.igloo.tag;
      expected = "PASSED-BY-CALLER";
    };
    test-an-instance-type-threads-its-special-args-to-the-kind-s-modules = {
      expr = viaType.config.host.tag;
      expected = "PASSED-BY-CALLER";
    };
    test-the-same-kind-without-special-args-is-refused-control = {
      expr = (builtins.tryEval (builtins.deepSeq withoutArgs.config.hosts.igloo.tag null)).success;
      expected = false;
    };
    # ★ THE IDENTITY ARM, AND IT IS A DIFFERENT FORCE FROM EVERY CELL ABOVE. Reading a DECLARED
    # option reaches the instance fixpoint, which the type-level inlet already serves. The
    # identity-key set is derived one stratum ABOVE that fixpoint, by a SECOND application of the
    # kind's modules inside `identityKeysForKind` — so a thread that stops at the inlet leaves that
    # application argument-less, and the kind module refuses under ADR-0033 the moment anything
    # forces it. Nothing forces it until `id_hash` (or `_identityKeys`) is read, which is why every
    # cell above passed while a consumer that stamps identities did not evaluate.
    test-the-identity-key-set-is-derived-with-the-caller-s-special-args = {
      expr = viaGatedType.config.host._identityKeys;
      expected = [
        "addr"
        "gate"
        "name"
      ];
    };
    # The consumer's own force. `id_hash` is what a stamping consumer reads, and it is the force
    # that caught this — a registry read reaches it for every element, which is why the reporting
    # config did not evaluate at all rather than failing only on identity.
    test-id-hash-evaluates-on-a-kind-whose-modules-need-an-arg = {
      expr = builtins.match "gated:[0-9a-f]{64}" viaGatedRegistry.config.hosts.igloo.id_hash != null;
      expected = true;
    };
    # LIVE CONTROL: a kind declaring no extra formal is untouched — a function module binds only the
    # formals it declares, so the thread is additive by construction.
    test-an-ordinary-instance-option-is-unaffected-control = {
      expr = viaRegistry.config.hosts.igloo.addr;
      expected = "10.0.1.1";
    };
  };
}
