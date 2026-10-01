# demo/flake.nix takes the hub, which pins this repository: an INTEGRATION example. Its lock is not
# committed (`/examples/demo/flake.lock` in the root `.gitignore`); `relock` locks it fresh in a
# scratch copy and forces this value over the working tree (den-hoag-tyu25).
{ exampleAtOwnLock, ... }:
{
  gen.ci.examples.demo = exampleAtOwnLock "demo" (flake: {
    inherit (flake) docs fleet;
  });
}
