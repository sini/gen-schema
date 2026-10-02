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
          nix-instantiate --eval --strict --readonly-mode "$@" \
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

        # 0/0 is a false pass: the runner must have executed every cell above.
        [ "$ran" = "8" ] || die runner "expected 8 evaluations, ran $ran"
        echo "tests-process: 8 cells, every exit read unpiped; kind mints $one for 1 instance and $eight for 8; spy control $control; refined predicate applications 1/1/1/3; attribution $attributed"
      '';
    };
}
