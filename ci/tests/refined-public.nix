# Public-surface reachability of the refined value-check. A downstream refined-facet contract calls
# `genSchema.checkRefinements`, so it must be on public `gen-schema.lib`, not only inside lib/refined.nix.
# checkRefinements returns a LIST of violation records (empty = pass); Findler & Felleisen 2002 / Rondon 2008.
{ genSchema, genMerge, ... }:
let
  refinedPositive = genSchema.refined genMerge.types.int [ genSchema.refinements.positive ];
in
{
  flake.tests.refined-public.test-check-refinements-is-public = {
    expr = genSchema ? checkRefinements;
    expected = true;
  };
  flake.tests.refined-public.test-public-check-valid = {
    expr = genSchema.checkRefinements "n" refinedPositive 5;
    expected = [ ];
  };
  flake.tests.refined-public.test-public-check-invalid-count = {
    expr = builtins.length (genSchema.checkRefinements "n" refinedPositive (-3));
    expected = 1;
  };
  flake.tests.refined-public.test-public-check-invalid-message = {
    expr = (builtins.head (genSchema.checkRefinements "n" refinedPositive (-3))).message;
    expected = "must be positive";
  };
}
