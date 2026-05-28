{
  lib,
  schemaLib,
  ...
}:
let
  inherit (schemaLib)
    mkSchemaOption
    mkInstanceRegistry
    ref
    setOf
    toSet
    ;

  # #1: Non-instance attrset passed to a ref field should throw
  evalBadAttrset = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption { };
        options.hosts = mkInstanceRegistry evalBadAttrset.config.schema "host" { };
        options.services = mkInstanceRegistry evalBadAttrset.config.schema "service" {
          refs.host = evalBadAttrset.config.hosts;
        };
        config.schema.host.options.addr = lib.mkOption { type = lib.types.str; };
        config.schema.service.options.host = lib.mkOption { type = ref "host"; };
        config.hosts.igloo = {
          addr = "10.0.1.1";
        };
        config.services.bad = {
          host = {
            foo = "bar";
          }; # not an instance
        };
      }
    ];
  };

  # #3: toSet on non-instances should throw
  evalGood = lib.evalModules {
    modules = [
      {
        options.schema = mkSchemaOption { };
        options.hosts = mkInstanceRegistry evalGood.config.schema "host" { };
        config.schema.host.options.addr = lib.mkOption { type = lib.types.str; };
        config.hosts.igloo = {
          addr = "10.0.1.1";
        };
      }
    ];
  };

  goodSet = toSet (builtins.attrValues evalGood.config.hosts);
in
{
  flake.tests.ref-validation-guards = {
    # #1: non-instance attrset in ref field
    test-non-instance-attrset-throws = {
      expr = builtins.tryEval (builtins.seq evalBadAttrset.config.services.bad.host null);
      expected = {
        success = false;
        value = false;
      };
    };

    # #2: dedupByHash on non-instances (exercised through toSet)
    test-dedup-non-instance-throws = {
      expr = builtins.tryEval (builtins.deepSeq (toSet [ { foo = "bar"; } ]) null);
      expected = {
        success = false;
        value = false;
      };
    };

    # #3: toSet.member on non-instance
    test-toset-member-non-instance-throws = {
      expr = builtins.tryEval (goodSet.member "not-an-instance");
      expected = {
        success = false;
        value = false;
      };
    };

    # #3: toSet on non-instances
    test-toset-non-instance-throws = {
      expr = builtins.tryEval (
        builtins.deepSeq (toSet [
          "foo"
          "bar"
        ]) null
      );
      expected = {
        success = false;
        value = false;
      };
    };

    # #5: setOf with non-ref element type
    test-setof-non-ref-throws = {
      expr = builtins.tryEval (builtins.seq (setOf lib.types.str) null);
      expected = {
        success = false;
        value = false;
      };
    };
  };
}
