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
  tagged.inletTag = "PASSED-BY-CALLER";

  # The kind's module forces its extra arg while DECLARING an option — the position that recurses
  # when the value can only come from `_module.args`.
  schema = evalSchema {
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
    # LIVE CONTROL: a kind declaring no extra formal is untouched — a function module binds only the
    # formals it declares, so the thread is additive by construction.
    test-an-ordinary-instance-option-is-unaffected-control = {
      expr = viaRegistry.config.hosts.igloo.addr;
      expected = "10.0.1.1";
    };
  };
}
