# Base validator constructors (gen-schema-owned), tested directly — distinct from
# the high-level validateInstances pipeline covered by validator-*.nix.
{ lib, genSchema, ... }:
let
  inherit (genSchema) mkValidator runValidators formatErrors;
  validators = [
    (mkValidator "has-addr" ({ addr, ... }: addr != "") "addr must not be empty")
  ];
  passResult = runValidators "host" validators {
    igloo = {
      addr = "10.0.1.1";
      role = "web";
    };
  };
  failResult = runValidators "host" validators {
    bad = {
      addr = "";
    };
  };
in
{
  flake.tests.runvalidators.test-pass-right-returned = {
    expr = passResult ? right;
    expected = true;
  };
  flake.tests.runvalidators.test-pass-right-contains-instances = {
    expr = passResult.right;
    expected = {
      igloo = {
        addr = "10.0.1.1";
        role = "web";
      };
    };
  };
  flake.tests.runvalidators.test-fail-left-returned = {
    expr = failResult ? left;
    expected = true;
  };
  flake.tests.runvalidators.test-fail-error-has-instance-name = {
    expr = (lib.head failResult.left).name;
    expected = "bad";
  };
  flake.tests.runvalidators.test-fail-error-has-validator-name = {
    expr = (lib.head failResult.left).validator;
    expected = "has-addr";
  };
  flake.tests.runvalidators.test-format-errors = {
    expr = formatErrors failResult.left;
    expected = "  host 'bad': has-addr — addr must not be empty";
  };
}
