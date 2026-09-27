# A declaration value resolves only when it IS a member of the target registry (den-hoag-a4158;
# den-hoag-2zjg1 arm (B)). One fixture, all three modes: direct (`declarationOf <registry>`),
# immediate (`refs.f = config.X`) and deferred (`refs.f = { deferred = true; … }`). Member cells stop
# an implementation that refuses every value; refusal cells stop one that admits every value; the
# canonical-entry cell stops one that checks membership but still serves the value it was handed.
# WHICH refusal fired is pinned in ../tests-error.nix (`declaration-membership-refusals`).
{
  genSchema,
  genMerge,
  ...
}:
let
  inherit (genSchema)
    evalSchema
    mkInstanceRegistry
    declarationOf
    setOf
    ;
  inherit (genMerge.types) str nullOr;
  opt = genMerge.mkOption;

  schema = evalSchema {
    modules = [
      {
        config.schema.host = {
          options.addr = opt { type = str; };
          options.note = opt {
            type = str;
            default = "n";
            identity = false;
          };
        };
        config.schema.service = {
          options.host = opt { type = declarationOf "host"; };
          options.peers = opt {
            type = setOf (declarationOf "host");
            default = [ ];
          };
        };
        config.schema.node = {
          options.addr = opt { type = str; };
          options.note = opt {
            type = str;
            default = "n";
            identity = false;
          };
          options.parent = opt {
            type = nullOr (declarationOf "node");
            default = null;
          };
        };
        config.schema.link.options.label = opt { type = str; };
      }
    ];
  };

  mk =
    extra:
    (genMerge.evalModuleTree {
      modules = [
        (
          { config, ... }:
          {
            options.hosts = mkInstanceRegistry schema.host { };
            options.spares = mkInstanceRegistry schema.host { };
            options.services = mkInstanceRegistry schema.service {
              refs = {
                host = config.hosts;
                peers = config.hosts;
              };
            };
            options.nodes = mkInstanceRegistry schema.node {
              refs.parent = {
                deferred = true;
                instances = config.nodes;
              };
            };
            options.links = mkInstanceRegistry schema.link {
              extraModules = [ { options.target = opt { type = declarationOf config.hosts; }; } ];
            };
            options.handLinks = mkInstanceRegistry schema.link {
              extraModules = [ { options.target = opt { type = declarationOf hand; }; } ];
            };
            config.hosts.igloo.addr = "10.0.0.1";
            config.hosts.yurt = {
              addr = "10.0.0.2";
              name = "renamed";
            };
            config.spares.igloo.addr = "10.9.9.9";
            config.nodes.n0.addr = "n0";
            config.links.main.label = "l";
            config.links.back.label = "b";
            config.handLinks.main.label = "l";
          }
        )
        extra
      ];
    }).config;

  # A stamp-bearing record that is not a gen-schema instance: no `_identityKeys` datum.
  hand.a = {
    name = "a";
    id_hash = "hand:1";
    addr = "x";
  };

  refused = v: !(builtins.tryEval (builtins.deepSeq v v)).success;
in
{
  flake.tests.declaration-membership = {
    test-direct-member-resolves = {
      expr =
        (mk ({ config, ... }: { config.links.main.target = config.hosts.igloo; })).links.main.target.addr;
      expected = "10.0.0.1";
    };
    # A member whose `name` is not its key: the name hint misses and the by-name index answers.
    test-direct-renamed-member-resolves = {
      expr =
        (mk ({ config, ... }: { config.links.main.target = config.hosts.yurt; })).links.main.target.addr;
      expected = "10.0.0.2";
    };
    test-immediate-member-resolves = {
      expr =
        (mk ({ config, ... }: { config.services.s.host = config.hosts.igloo; })).services.s.host.addr;
      expected = "10.0.0.1";
    };
    # The referenced node has had its own deferred field resolved, so the value handed over is the
    # post-apply record and the registry holds the raw one. They are one declaration.
    test-deferred-applied-member-resolves = {
      expr =
        (mk (
          { config, ... }:
          {
            config.nodes.root.addr = "root";
            config.nodes.n0.parent = "root";
            config.nodes.n1 = {
              addr = "n1";
              parent = config.nodes.n0;
            };
          }
        )).nodes.n1.parent.addr;
      expected = "n0";
    };
    # The door serves the registry's entry, never the value it was handed.
    test-resolves-to-the-canonical-entry = {
      expr =
        (mk (
          { config, ... }: {
            config.links.main.target = config.hosts.igloo // {
              note = "x";
            };
          }
        )).links.main.target.note;
      expected = "n";
    };
    test-immediate-resolves-to-the-canonical-entry = {
      expr =
        (mk (
          { config, ... }: {
            config.services.s.host = config.hosts.igloo // {
              note = "x";
            };
          }
        )).services.s.host.note;
      expected = "n";
    };
    test-deferred-resolves-to-the-canonical-entry = {
      expr =
        (mk (
          { config, ... }: {
            config.nodes.n1 = {
              addr = "n1";
              parent = config.nodes.n0 // {
                note = "x";
              };
            };
          }
        )).nodes.n1.parent.note;
      expected = "n";
    };
    test-direct-override-refused = {
      expr =
        refused
          (mk (
            { config, ... }: {
              config.links.main.target = config.hosts.igloo // {
                addr = "evil";
              };
            }
          )).links.main.target;
      expected = true;
    };
    test-immediate-foreign-refused = {
      expr =
        refused
          (mk ({ config, ... }: { config.services.s.host = config.spares.igloo; })).services.s.host;
      expected = true;
    };
    test-setof-foreign-refused = {
      expr =
        refused
          (mk (
            { config, ... }: {
              config.services.s = {
                host = "igloo";
                peers = [ config.spares.igloo ];
              };
            }
          )).services.s.peers;
      expected = true;
    };
    test-deferred-override-refused = {
      expr =
        refused
          (mk (
            { config, ... }: {
              config.nodes.n1 = {
                addr = "n1";
                parent = config.nodes.n0 // {
                  addr = "evil";
                };
              };
            }
          )).nodes.n1.parent;
      expected = true;
    };
    test-deferred-other-kind-refused = {
      expr =
        refused
          (mk (
            { config, ... }: {
              config.nodes.n1 = {
                addr = "n1";
                parent = config.hosts.igloo;
              };
            }
          )).nodes.n1.parent;
      expected = true;
    };
    test-direct-non-instance-refused = {
      expr =
        refused
          (mk {
            config.links.main.target = {
              name = "ghost";
            };
          }).links.main.target;
      expected = true;
    };
    # Without the `_identityKeys` datum the verdict would fall back to the copied stamp and admit
    # the override, dropping its edit silently. WHICH refusal fired is pinned in ../tests-error.nix.
    test-direct-override-of-a-non-instance-refused = {
      expr =
        refused
          (mk {
            config.handLinks.main.target = hand.a // {
              addr = "evil";
            };
          }).handLinks.main.target;
      expected = true;
    };
    # Gate v1 C3: the identifier form never reads identity, so it is the escape from the
    # uncatchable class in ../../lib/ref.nix's header. The value forms of these three abort with
    # `infinite recursion`, which `tryEval` cannot hold; they are driven out of suite.
    test-self-identity-identifier-evaluates = {
      expr =
        (mk (
          { config, ... }:
          {
            config.links.main.target = "cabin";
            config.hosts.cabin.addr = config.links.main.target.note + "-c";
          }
        )).hosts.cabin.addr;
      expected = "n-c";
    };
    test-mutual-identity-identifier-evaluates = {
      expr =
        (mk (
          { config, ... }:
          {
            config.links.main.target = "cabin";
            config.links.back.target = "hut";
            config.hosts.hut.addr = config.links.main.target.note + "-h";
            config.hosts.cabin.addr = config.links.back.target.note + "-c";
          }
        )).hosts.hut.addr;
      expected = "n-h";
    };
    test-name-via-renamed-identifier-evaluates = {
      expr =
        (mk (
          { config, ... }:
          {
            config.links.main.target = "yurt";
            config.hosts.cabin = {
              addr = "10.0.0.3";
              name = config.links.main.target.note + "-c";
            };
          }
        )).hosts.cabin.name;
      expected = "n-c";
    };
    # Gate v0 C1: a member's identity key computed through a declaration value naming a renamed
    # member. The resolver forces the candidate's identity and every member's `name`, never every
    # member's `id_hash`, so this evaluates.
    test-renamed-cycle-evaluates = {
      expr =
        (mk (
          { config, ... }:
          {
            config.links.main.target = config.hosts.yurt;
            config.hosts.cabin.addr = config.links.main.target.addr + "-c";
          }
        )).hosts.cabin.addr;
      expected = "10.0.0.2-c";
    };
  };
}
