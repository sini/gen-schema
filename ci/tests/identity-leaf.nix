# `_identity` is a closed `lazyAttrsOf (listOf str)` leaf, not a submodule (den-hoag-xzchx arm 4).
#
# The record is closed to `keys` by the option's own `apply`, not by a nested declaration plane, so
# the cells below pin the three things the leaf owns that nothing else in this suite pinned: the
# option's type, that a key other than `keys` refuses on every kind strictness (a conditioned-away
# one included), and that a module-shaped definition refuses. The value cells pin what the change
# must NOT move. The messages live in ci/tests-error.nix (`identity-leaf-refusals`).

{
  genSchema,
  genMerge,
  ...
}:

let
  inherit (genSchema)
    mkIdentityModule
    identityKeysForKind
    evalSchema
    mkInstanceRegistry
    ;
  t = genMerge.types;

  # The direct door: `mkIdentityModule` applied to a kind declared through `evalSchema`, as
  # ci/tests/identity-explicit-keys.nix does. Its `options._identity` is the option under test.
  hostDecl = {
    options.name = genMerge.mkOption { type = t.str; };
    options.addr = genMerge.mkOption { type = t.str; };
  };
  kindValue = (evalSchema { modules = [ { config.schema.host = hostDecl; } ]; }).host;
  direct =
    extra:
    genMerge.evalModuleTree {
      modules = [
        (mkIdentityModule kindValue (identityKeysForKind { } kindValue))
        hostDecl

        {
          config.name = "igloo";
          config.addr = "10.0.0.1";
        }

      ]
      ++ extra;
    };
  identityType = (direct [ ]).options._identity.type;

  # The published path: an instance of a registry, on a strict kind (the default) and a lax one.
  frozenHost =
    (evalSchema {
      modules = [

        {
          config.schema.host.options.addr = genMerge.mkOption { type = t.str; };
          config.schema.host.options.role = genMerge.mkOption { type = t.str; };
        }

      ];
    }).host;
  one =
    regOpts: v:
    (genMerge.evalModuleTree {
      modules = [

        {
          options.hosts = mkInstanceRegistry frozenHost regOpts;
          config.hosts.h = {
            addr = "10.0.0.1";
            role = "web";
          }
          // v;
        }

      ];
    }).config.hosts.h;
  read = h: {
    inherit (h) id_hash _identity _identityKeys;
  };
  forced = h: (builtins.tryEval (builtins.deepSeq (read h) true)).success;
  bogusIfFalse = genMerge.mkIf false [ "x" ];
in

{
  flake.tests.identity-leaf = {
    # The touched surface. A submodule here is the construction this landing retires; the nested
    # tree it builds per instance is the whole of the cost (xzchx arm-3 scout, §2). `lazyAttrsOf`,
    # not `attrsOf`: the latter drops a conditioned-away key before `apply` can refuse it.
    test-type-is-lazyAttrsOf-listOf-str = {
      expr = {
        outer = identityType.name;
        middle = identityType.nestedTypes.elemType.name or null;
        inner = identityType.nestedTypes.elemType.nestedTypes.elemType.name or null;
      };
      expected = {
        outer = "lazyAttrsOf";
        middle = "listOf";
        inner = "string";
      };
    };

    # The record is closed: a key other than `keys` refuses, on a strict kind and on a lax one. A
    # lax kind's freeform must not absorb it, and a `mkIf false` one must not vanish silently,
    # alone or beside `keys`. The control arm is the same fixture with `keys` only.
    test-foreign-key-refuses = {
      expr = {
        strict = forced (one { } { _identity.bogus = [ "x" ]; });
        lax = forced (one { strict = false; } { _identity.bogus = [ "x" ]; });
        strictIfFalse = forced (one { } { _identity.bogus = bogusIfFalse; });
        laxIfFalse = forced (one { strict = false; } { _identity.bogus = bogusIfFalse; });
        besideKeysIfFalse = forced (
          one { } {
            _identity = {
              keys = [ "addr" ];
              bogus = bogusIfFalse;
            };
          }
        );
        control = forced (one { } { _identity.keys = [ "addr" ]; });
      };
      expected = {
        strict = false;
        lax = false;
        strictIfFalse = false;
        laxIfFalse = false;
        besideKeysIfFalse = false;
        control = true;
      };
    };

    # A module-shaped definition — a function, a path, or an attrset carrying module keys — is
    # outside the leaf's domain and refuses; it no longer reaches a nested declaration plane at all.
    test-module-shaped-definition-refuses = {
      expr = {
        function = forced (one { } { _identity = { config, ... }: { keys = [ "addr" ]; }; });
        configKey = forced (one { } { _identity.config.keys = [ "addr" ]; });
        declReadsConfig = forced (
          one { } {
            _identity =
              { config, ... }:
              {
                options = if config.keys == [ ] then { } else { };
              };
          }
        );
        notASet = forced (one { } { _identity = 5; });
        path = forced (one { } { _identity = ../test-fixtures/identity-path-definition.nix; });
        imports = forced (one { } { _identity.imports = [ { keys = [ "addr" ]; } ]; });
        moduleArgs = forced (
          one { } {
            _identity = {
              keys = [ "addr" ];
              _module.args = { };
            };
          }
        );
      };
      expected = {
        function = false;
        configKey = false;
        declReadsConfig = false;
        notASet = false;
        path = false;
        imports = false;
        moduleArgs = false;
      };
    };

    # What the change must not move: `keys` merges as a list, `unique` holds under every priority
    # wrapper, and an absent or conditioned-away definition reads as no keys.
    test-keys-values-unmoved = {
      expr = {
        dup =
          (one { } {
            _identity.keys = [
              "addr"
              "addr"
            ];
          })._identity;
        ifTrue = (one { } { _identity = genMerge.mkIf true { keys = [ "role" ]; }; })._identity;
        ifFalse = (one { } { _identity = genMerge.mkIf false { keys = [ "addr" ]; }; })._identity;
        keysIfFalse = (one { } { _identity.keys = genMerge.mkIf false [ "addr" ]; })._identity;
        force =
          (one { } {
            _identity.keys = genMerge.mkForce [
              "addr"
              "addr"
            ];
          })._identity;
        default = (one { } { _identity.keys = genMerge.mkDefault [ "addr" ]; })._identity;
        empty = (one { } { _identity = { }; })._identity;
        unset = (one { } { })._identity;
        # the digest the keys feed, reflected and explicit
        hashReflected = (one { } { }).id_hash;
        hashExplicit = (one { } { _identity.keys = [ "addr" ]; }).id_hash;
      };
      expected = {
        dup.keys = [ "addr" ];
        ifTrue.keys = [ "role" ];
        ifFalse.keys = [ ];
        keysIfFalse.keys = [ ];
        force.keys = [ "addr" ];
        default.keys = [ "addr" ];
        empty.keys = [ ];
        unset.keys = [ ];
        hashReflected = "host:40aa9c14f591155a0804aebe7b96f7606295a3f424207a7fdeb56731c18cc7e1";
        hashExplicit = "host:d7aedf042f783b3c7d14ffbc1228dad310f8be3b082a90b1ed2432a8bdf27da2";
      };
    };
  };
}
