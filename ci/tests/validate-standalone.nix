# validateInstances is a standalone function that returns Either without throwing.
# It operates independently of the registry pipeline.
{
  lib,
  genSchema,
  genMerge,
  genAlgebra,
  ...
}:
let
  inherit (genSchema) mkValidator;

  # A bogus kind value -- no `kind`/`options`, the shape validateInstances' guard rejects.
  bogus = {
    no = "kind";
  };

  # Build schema with validators, but create instances manually (not via registry)
  # to avoid the registry's apply pipeline throwing on validation failure.
  schemaEval = genMerge.evalModuleTree {
    modules = [
      {
        options.schema = genSchema.mkSchemaOption { };
        config.schema.host = {
          options.addr = genMerge.mkOption { type = genMerge.types.str; };
          validators = [
            (genSchema.mkValidator "has-addr" ({ addr, ... }: addr != "") "need addr")
          ];
        };
      }
    ];
  };

  # Create instances directly via mkInstanceType (no apply pipeline)
  hostType = genSchema.mkInstanceType schemaEval.config.schema.host { };
  instanceEval = genMerge.evalModuleTree {
    modules = [
      {
        options.hosts = genMerge.mkOption {
          type = genMerge.types.attrsOf hostType;
          default = { };
        };
        config.hosts.good.addr = "10.0.1.1";
        config.hosts.bad.addr = "";
      }
    ];
  };

  result = genSchema.validateInstances schemaEval.config.schema.host instanceEval.config.hosts;
in
{
  flake.tests."validate-standalone".test-returns-either = {
    expr = result ? left || result ? right;
    expected = true;
  };
  flake.tests."validate-standalone".test-has-errors = {
    expr = result ? left;
    expected = true;
  };
  flake.tests."validate-standalone".test-does-not-throw = {
    expr = (builtins.tryEval result).success;
    expected = true;
  };

  # den-hoag-fvxh: the kind-value guard used to be silent here -- an empty instance set, and an
  # all-passing one, never forced kindValue.kind, so a bogus kind value slipped through undetected.
  # Both now throw the guard's own assert, checked in the same run as test-does-not-throw above
  # (the real-kind positive control: a well-formed kind never trips this guard).
  flake.tests."validate-standalone".test-bogus-empty-set-throws = {
    expr = (builtins.tryEval (genSchema.validateInstances bogus { })).success;
    expected = false;
  };
  flake.tests."validate-standalone".test-bogus-all-pass-set-throws = {
    expr =
      (builtins.tryEval (
        genSchema.validateInstances bogus {
          a = {
            port = 1;
          };
        }
      )).success;
    expected = false;
  };
  # Already threw before the fix (a failing validator forces `kind` to build its failure record);
  # pinned here so a future regression on this arm is caught alongside the two that were silent.
  flake.tests."validate-standalone".test-bogus-with-failing-validator-still-throws = {
    expr =
      (builtins.tryEval (
        genSchema.validateInstances { validators = [ (mkValidator "v" (_: false) "m") ]; } { a = { }; }
      )).success;
    expected = false;
  };
}
