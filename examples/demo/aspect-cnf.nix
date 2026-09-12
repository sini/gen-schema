# THE SHARED HOME for this tree's aspect-declaration input (ADR-0028's Rider; gen-delivery's
# `requireCnf`, wired in by `gen.aspectCnf`). This demo declares NO aspect keys anywhere in
# `./gen-modules` — there is no `genAspects.mkAspectSchema` call, no `schema.aspect` kind, no
# `config.aspects`/`options.aspects` (verified: grep across the whole tree for
# genAspects/mkAspectSchema/mkAspectOption/aspectsRoot/config.aspects/options.aspects ⇒ zero hits).
# The truthful `cnf` is the empty declaration below, not a placeholder standing in for a real one.
#
# Lives OUTSIDE `gen.tree` — a sibling of `flake.nix`, not under `./gen-modules` — because
# import-tree sweeps every file under `gen.tree` into the composed module list, and a bare attrset
# dropped there is itself a module contribution: `{ keySemantics = {}; }` inside `gen-modules/` would
# merge as a spurious top-level `config.keySemantics` on the composed values, not stay data.
#
# `gen.aspectCnf`'s own description names the trap this file avoids: the declaration cannot be read
# back out of the compose result, because `keySemantics` only reaches `values.schema.<kind>` when the
# tree also DEFINES a schema kind entry — a tree that (like this one) defines none would silently
# re-derive `{}` either way, masking the day this tree actually adds a `schema.aspect` kind. So this
# is the ONE file both `flake.nix`'s `gen.aspectCnf` and any future aspect-schema module import,
# rather than each holding its own copy that can drift.
{
  keySemantics = { };
}
