# Structured blame error constructor for field-level attribution.
# This is producer-side error reporting (which field, which predicate),
# not § Chitil 2012 higher-order lazy blame. See lazy contracts in instance.nix
# for the § Chitil 2012 deferred validation mechanism.
# Dependency-free (pure builtins), so this is a bare value (gen convention §8).
{
  blame = field: message: {
    __blame = true;
    inherit field message;
  };

  isBlame = v: builtins.isAttrs v && v ? __blame;

  collectBlame = results: builtins.filter (r: r != null && builtins.isAttrs r && r ? __blame) results;
}
