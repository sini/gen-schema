# THE PER-PROCESS RUNNER — evaluates each cell in `tests-process-cells.nix` in its OWN evaluator
# process and asserts on the exit status, the printed value and a spy's trace count. gen-merge's and
# gen-scope's `ci/tests-process.nix` are the precedent: the verdict is a process predicate, so it is
# not a nix-unit output, and it is evidence only for the evaluator that computed it, so it is not a
# sandboxed check. As `apps.<system>.tests-process` its cells call the `nix-instantiate` on PATH, and
# gen-harness's `ci --tests-process` runs it in every column of `evaluators.yml`. Locally:
#   nix develop ./ci --command ci --tests-process
{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      apps.tests-process.program = pkgs.writeShellScriptBin "tests-process" ''
        set -e
        # The tools the body calls, declared rather than ambient — and never an evaluator.
        export PATH=${
          pkgs.lib.makeBinPath [
            pkgs.coreutils
            pkgs.gnugrep
            pkgs.gnused
          ]
        }:$PATH
        cells=${./tests-process-cells.nix}
        TMPDIR=$(mktemp -d)
        export TMPDIR
        trap 'rm -rf "$TMPDIR"' EXIT
        cd "$TMPDIR"
        export NIX_STATE_DIR=$TMPDIR/nix-state NIX_LOG_DIR=$TMPDIR/nix-log
        echo "evaluator: $(nix-instantiate --version | sed -n 1p)"
        # A thunk count is defined only for a serial run, so the counted cells below (`cellThunks`) are
        # serial, and every other cell runs under the column's own evaluator, Determinate's parallel one
        # included. The options are resolved once (gen-harness `lib.serialEval`); `inst` carries them only
        # while NIX_SHOW_STATS is set, so a counted cell cannot run unpinned, nor a correctness cell pinned.
        # shellcheck disable=SC1091
        source ${inputs.gen-harness.lib.serialEval { inherit pkgs; }}
        serialEvalOptions "$(command -v nix-instantiate)" || {
          echo "tests-process: CONTROL FAILED: the serial options of $(command -v nix-instantiate) could not be resolved" >&2
          exit 2
        }
        echo "tests-process: serial options: ''${SERIAL_EVAL[*]:-(none)}"
        ran=0
        # The spy's trace label, generated fresh per run and never written down, so no text a cell
        # or a document carries can be mistaken for a firing.
        label="spy-$(head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n')"
        die() {
          echo "tests-process: FAILED at cell $1: $2" >&2
          exit 1
        }
        # inst <flag>...: one evaluation of the cells file, in its own process.
        inst() {
          nix-instantiate ''${NIX_SHOW_STATS:+"''${SERIAL_EVAL[@]}"} --eval --strict --readonly-mode "$@" \
            --argstr label "$label" \
            --argstr libSrc ${../lib} \
            --argstr preludeSrc ${inputs.gen-prelude} \
            --argstr identitySrc ${inputs.gen-identity} \
            --argstr graphSrc ${inputs.gen-graph} \
            --argstr algebraSrc ${inputs.gen-algebra} \
            --argstr typesSrc ${inputs.gen-merge.inputs.gen-types} \
            --argstr memoSrc ${inputs.gen-merge.inputs.gen-memo} \
            --argstr scopeSrc ${inputs.gen-merge.inputs.gen-scope} \
            --argstr mergeSrc ${inputs.gen-merge} \
            "$cells"
        }
        # evalArm <arm>: runs one cell in its own process; leaves rc, val and n (the spy's count) set.
        evalArm() {
          rc=0
          val=$(inst --argstr arm "$1" 2> "$TMPDIR/err") || rc=$?
          n=$(grep -c "trace: $label\$" "$TMPDIR/err" || true)
          ran=$((ran + 1))
          [ "$rc" -eq 0 ] || die "$1" "expected exit 0, got $rc: $(tail -n 3 "$TMPDIR/err")"
        }

        # den-hoag-l0y G2 · the kind module's key reads the kind's mark, bound once per kind: the marks
        # minted for one kind do not move with its instance count. A mint inside `__functor` would run
        # once per instance and read 7 more here.
        evalArm mints-one-instance
        [ "$val" = "1" ] || die mints-one-instance "expected value 1, got '$val'"
        one=$n
        evalArm mints-eight-instances
        [ "$val" = "8" ] || die mints-eight-instances "expected value 8, got '$val'"
        eight=$n
        [ "$one" -ge 1 ] || die mints-one-instance "the spy counted no mint at all"
        [ "$eight" = "$one" ] || die mints-eight-instances "kind mints moved with the instance count: $one for 1 instance, $eight for 8"
        # The spy's live control: eight independent kinds mint at least eight times.
        evalArm mints-eight-kinds
        [ "$val" = "8" ] || die mints-eight-kinds "expected value 8, got '$val'"
        [ "$n" -ge 8 ] || die mints-eight-kinds "the spy's control expected at least 8 mints, counted $n"

        control=$n

        # den-hoag-a7c9r U1 · the constant component tags are minted once per evaluation: one component
        # mint per parentless kind beside them, so four kinds mint three more than one kind does.
        evalArm component-mints-one-kind
        [ "$val" = "1" ] || die component-mints-one-kind "expected value 1, got '$val'"
        c1=$(grep -c "trace: $label-component\$" "$TMPDIR/err" || true)
        evalArm component-mints-four-kinds
        [ "$val" = "4" ] || die component-mints-four-kinds "expected value 4, got '$val'"
        c4=$(grep -c "trace: $label-component\$" "$TMPDIR/err" || true)
        [ "$c1" -ge 1 ] || die component-mints-one-kind "the spy counted no component mint at all"
        [ "$c1" = "3" ] && [ "$c4" = "6" ] ||
          die component-mints-four-kinds "expected 3 component mints for 1 kind and 6 for 4 (one per kind and the two constants once), counted $c1 and $c4"

        # den-hoag-a7c9r V1-a C2 · an `mkType`-arm kind's mark is bound once, read by `__mint` and by
        # the node record gen-merge reads where two constructions meet: two constructions mint two marks.
        evalArm mktype-two-constructions-mints
        [ "$val" = "2" ] || die mktype-two-constructions-mints "expected value 2, got '$val'"
        [ "$n" = "2" ] || die mktype-two-constructions-mints "expected 2 kind mints (one per construction), counted $n"

        # den-hoag-refined-outside-kind-silent-1jlsq · a refined type applies each predicate once per
        # demanded value, inside a kind (strict or lazy) and outside one.
        for c in refined-cost-in-kind:5:1 refined-cost-in-kind-lazy:5:1 refined-cost-outside:5:1 \
          "refined-cost-outside-list:[ 1 2 3 ]:3"; do
          cell=''${c%%:*}
          rest=''${c#*:}
          evalArm "$cell"
          [ "$val" = "''${rest%:*}" ] || die "$cell" "expected value ''${rest%:*}, got '$val'"
          [ "$n" = "''${rest##*:}" ] || die "$cell" "expected ''${rest##*:} predicate applications, counted $n"
        done
        # An ill-typed predicate aborts uncatchably, and the abort names the refinement. --show-trace is
        # passed here rather than read from nix.conf: without it Lix truncates the frame that names it.
        rc=0
        inst --show-trace --argstr arm refined-attribution > /dev/null 2> "$TMPDIR/err" || rc=$?
        ran=$((ran + 1))
        [ "$rc" -ne 0 ] || die refined-attribution "expected a refusal, got exit 0"
        grep -q 'cannot compare an integer with a string' "$TMPDIR/err" ||
          die refined-attribution "expected the comparison abort: $(tail -n 3 "$TMPDIR/err")"
        attributed=$(grep -c 'gen-schema: refined: while checking the refinement "must be positive"' "$TMPDIR/err" || true)
        [ "$attributed" = "1" ] || die refined-attribution "expected 1 attribution line, counted $attributed"

        # den-hoag-ux9xg · an identity-bearing collection that reads its own kind's instance aborts
        # uncatchably, and the abort names the kind and the collection. --show-trace as above.
        rc=0
        inst --show-trace --argstr arm collection-identity-guard > /dev/null 2> "$TMPDIR/err" || rc=$?
        ran=$((ran + 1))
        [ "$rc" -ne 0 ] || die collection-identity-guard "expected an abort, got exit 0"
        grep -q 'infinite recursion' "$TMPDIR/err" ||
          die collection-identity-guard "expected the recursion abort: $(tail -n 3 "$TMPDIR/err")"
        guarded=$(grep -c "gen-schema: while minting the identity of kind 'host' over its component 'collections.excludes'" "$TMPDIR/err" || true)
        [ "$guarded" -ge 1 ] || die collection-identity-guard "expected the attribution naming 'collections.excludes', counted 0"

        # den-hoag-ux9xg C1 · a computed field partial on the projected declaration aborts, attributed.
        rc=0
        inst --show-trace --argstr arm computed-projection-attribution > /dev/null 2> "$TMPDIR/err" || rc=$?
        ran=$((ran + 1))
        [ "$rc" -ne 0 ] || die computed-projection-attribution "expected an abort, got exit 0"
        projected=$(grep -c "gen-schema: while minting the identity of kind 'host' over its component 'computed.firstTag'" "$TMPDIR/err" || true)
        [ "$projected" -ge 1 ] || die computed-projection-attribution "expected the attribution naming 'computed.firstTag', counted 0"

        # den-hoag-ux9xg C1 · the same abort met through an instance read (the stamp's path), attributed.
        rc=0
        inst --show-trace --argstr arm computed-projection-instance > /dev/null 2> "$TMPDIR/err" || rc=$?
        ran=$((ran + 1))
        [ "$rc" -ne 0 ] || die computed-projection-instance "expected an abort, got exit 0"
        projectedInst=$(grep -c "gen-schema: while minting the identity of kind 'host' over its component 'computed.firstTag'" "$TMPDIR/err" || true)
        [ "$projectedInst" -ge 1 ] || die computed-projection-instance "expected the attribution naming 'computed.firstTag', counted 0"

        # den-hoag-ux9xg C1 · the guard over a collection whose tag sorts after every built-in's.
        rc=0
        inst --show-trace --argstr arm collection-identity-guard-sorted-last > /dev/null 2> "$TMPDIR/err" || rc=$?
        ran=$((ran + 1))
        [ "$rc" -ne 0 ] || die collection-identity-guard-sorted-last "expected an abort, got exit 0"
        grep -q 'infinite recursion' "$TMPDIR/err" ||
          die collection-identity-guard-sorted-last "expected the recursion abort: $(tail -n 3 "$TMPDIR/err")"
        guardedLast=$(grep -c "gen-schema: while minting the identity of kind 'host' over its component 'collections.zones'" "$TMPDIR/err" || true)
        [ "$guardedLast" -ge 1 ] || die collection-identity-guard-sorted-last "expected the attribution naming 'collections.zones', counted 0"

        # Kinds meet by declaration node, so the instance read beside another tree's same-named kind
        # composes and reads the instance's own address.
        rc=0
        residue=$(inst --argstr arm inheriting-same-name-residue 2> "$TMPDIR/err") || rc=$?
        ran=$((ran + 1))
        [ "$rc" -eq 0 ] || die inheriting-same-name-residue "expected the address, got rc $rc: $(tail -n 3 "$TMPDIR/err")"
        [ "$residue" = '"10.0.1.1"' ] || die inheriting-same-name-residue "expected \"10.0.1.1\", got $residue"

        # den-hoag-f1iza G1 · a kind chain's cost is linear in its depth: one host of the deepest kind of
        # a 16-, 32- and 64-deep chain (values and `id_hash`), the per-level slope from 32 to 64 over the
        # slope from 16 to 32 at most 1.30. A cost quadratic in depth doubles the slope per doubling (the
        # bundle without the layering reads 1.82, main 1.84); the layered chain reads 1.11 on Nix,
        # Determinate and Lix. The value, not the counts, is pinned: counts differ by evaluator. Scope:
        # single-parent chains of plain attrset kinds at k <= 64; the inheritance-cycle walk's own
        # quadratic term is present and within the bound (den-hoag-f1iza OQ-2).
        thunks=""
        cellThunks() {
          rm -f "$TMPDIR/stats"
          rc=0
          export NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH="$TMPDIR/stats"
          val=$(inst --argstr arm "$1" 2> "$TMPDIR/err") || rc=$?
          unset NIX_SHOW_STATS NIX_SHOW_STATS_PATH
          ran=$((ran + 1))
          [ "$rc" -eq 0 ] || die "$1" "expected exit 0, got $rc: $(tail -n 3 "$TMPDIR/err")"
          thunks=$(tr -d ' \n' < "$TMPDIR/stats" | grep -o '"nrThunks":[0-9]*' | cut -d: -f2 || true)
          [ -n "$thunks" ] || die "$1" "the evaluator wrote no nrThunks to $TMPDIR/stats: cannot measure"
        }
        cellThunks depth-host-16
        [ "$val" = "64" ] || die depth-host-16 "expected value 64, got '$val'"
        d16=$thunks
        cellThunks depth-host-32
        [ "$val" = "128" ] || die depth-host-32 "expected value 128, got '$val'"
        d32=$thunks
        cellThunks depth-host-64
        [ "$val" = "256" ] || die depth-host-64 "expected value 256, got '$val'"
        d64=$thunks
        s1=$(((d32 - d16) / 16))
        s2=$(((d64 - d32) / 32))
        [ "$s1" -gt 0 ] || die depth-host-32 "the slope from 16 to 32 is $s1 thunks per level: cannot measure"
        [ $((s2 * 100)) -le $((s1 * 130)) ] ||
          die depth-host-64 "a kind chain's cost is superlinear in depth: $s1 thunks per level from 16 to 32, $s2 from 32 to 64, a ratio over 1.30"

        # den-hoag-ien5k T3 GS4 · the membership read forces no kind- or node-side `mkIf` condition: each plant's
        # condition is an `abort`, which `tryEval` cannot catch, so a forced condition is a nonzero exit. The kind
        # plant falls back on all 4 nodes and the node plants on 1. The control is the module read of the same
        # fleet, which forces the condition (or refuses the `mkForce (mkIf …)` plant by name, a refusal-parity
        # control and not a forcing plant), so every condition is live in this run.
        for plant in kind:4 node:1 merge:1 force:1; do
          evalArm "declared-unforced-''${plant%:*}"
          [ "$val" = "''${plant##*:}" ] || die "declared-unforced-''${plant%:*}" "expected ''${plant##*:} nodes to fall back, got '$val'"
          rc=0
          inst --argstr arm "declared-control-''${plant%:*}" > /dev/null 2> "$TMPDIR/err" || rc=$?
          ran=$((ran + 1))
          [ "$rc" -ne 0 ] || die "declared-control-''${plant%:*}" "expected the module read to force or refuse, got exit 0"
          if [ "''${plant%:*}" = force ]; then
            grep -q "listOf' cannot consume" "$TMPDIR/err" || die declared-control-force "expected the refusal by name: $(tail -n 3 "$TMPDIR/err")"
          else
            grep -q "ien5k-t3: ''${plant%:*} mkIf condition forced" "$TMPDIR/err" ||
              die "declared-control-''${plant%:*}" "expected the plant's abort: $(tail -n 3 "$TMPDIR/err")"
          fi
        done

        # den-hoag-ien5k T3 GS2 · the reader's per-node cost over a registry, N 4 to 16, at or below its landed
        # figure, and below the module read's on the same fixture (the RED).
        cellThunks declared-cost-4
        [ "$val" = "0" ] || die declared-cost-4 "expected every node served, got '$val' falling back"
        r4=$thunks
        cellThunks declared-cost-16
        [ "$val" = "0" ] || die declared-cost-16 "expected every node served, got '$val' falling back"
        r16=$thunks
        cellThunks module-read-cost-4
        m4=$thunks
        cellThunks module-read-cost-16
        m16=$thunks
        rs=$(((r16 - r4) / 12))
        ms=$(((m16 - m4) / 12))
        [ "$rs" -gt 0 ] || die declared-cost-16 "the reader's slope is $rs thunks per node: cannot measure"
        [ "$rs" -le 97 ] || die declared-cost-16 "the reader costs $rs thunks per node, over the landed 97"
        [ "$rs" -lt "$ms" ] || die module-read-cost-16 "the reader costs $rs thunks per node, not below the module read's $ms"

        # den-hoag-ien5k T3 GS2 · a fallback costs the reader nothing per node where the kind sets the field bare: the
        # registry-level test (a registry-side definition at gen-merge's `defaultOverridePriority`) decides it once.
        cellThunks declared-fallback-cost-4
        [ "$val" = "4" ] || die declared-fallback-cost-4 "expected every node to fall back, got '$val'"
        f4=$thunks
        cellThunks declared-fallback-cost-16
        [ "$val" = "16" ] || die declared-fallback-cost-16 "expected every node to fall back, got '$val'"
        f16=$thunks
        fs=$(((f16 - f4) / 12))
        [ "$fs" -le 1 ] || die declared-fallback-cost-16 "a fallback costs the reader $fs thunks per node, over 1: the registry-level test did not decide it"

        # den-hoag-ien5k T3 GS2 · C7: the reader's own cost at one node, over the registry's evaluation, at or below its
        # landed figure: it reads the declarations the registry record states, never a second evaluation of the
        # element's option tree (`getSubOptions [ ]`, which the record's `options` dropped reads at about 1,500).
        cellThunks declared-own-base-1
        [ "$val" = "1" ] || die declared-own-base-1 "expected value 1, got '$val'"
        o0=$thunks
        cellThunks declared-own-1
        [ "$val" = "0" ] || die declared-own-1 "expected the node served, got '$val' falling back"
        own1=$((thunks - o0))
        [ "$own1" -gt 0 ] || die declared-own-1 "the reader's own cost is $own1 thunks: cannot measure"
        [ "$own1" -le 361 ] || die declared-own-1 "the reader costs $own1 thunks at one node, over the landed 361"

        # 0/0 is a false pass: the runner must have executed every cell above.
        [ "$ran" = "35" ] || die runner "expected 35 evaluations, ran $ran"
        echo "tests-process: 33 cells, every exit read unpiped; declaredField unforced on 4 plants, controls live; declaredField $rs thunks per node against the module read's $ms, a kind-set fallback $fs, its own cost at one node $own1; kind mints $one for 1 instance and $eight for 8; spy control $control; component mints $c1 for 1 kind and $c4 for 4; mkType two-construction mints 2; refined predicate applications 1/1/1/3; attribution $attributed; identity guard $guarded / $guardedLast; projection $projected / $projectedInst; depth thunks $d16 / $d32 / $d64, slopes $s1 / $s2 thunks per level"
      '';
    };
}
