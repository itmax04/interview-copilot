#!/usr/bin/env bash
# Прогон evals (evals/README.md): scripts/run-evals.sh [bank|turn|filter-text|filter]  (без аргумента — все наборы).
# Результат: сводка в stdout и JSON-лог в evals/results/ (в Git не попадает). Код возврата 1, если порог не выполнен.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
swift build -c release --product copilot-eval >/dev/null
BIN="$(swift build -c release --show-bin-path)/copilot-eval"
mkdir -p evals/results
STAMP="$(date +%Y-%m-%d-%H%M%S)"
# filter-text — без моделей; filter (звук, нужны Parakeet и Silero) — отдельно: scripts/run-evals.sh filter
suites=("${@:-turn bank filter-text}")
status=0
for suite in ${suites[@]}; do
  out="evals/results/$suite-$STAMP.txt"
  if "$BIN" "$suite" | tee "$out"; then :; else status=1; fi
done
exit $status
