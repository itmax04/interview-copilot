#!/usr/bin/env bash
# Поиск ключей и личных данных в репозитории (AC-06, plan.md P-01). Запускать перед каждым push.
#   scripts/secret-scan.sh            — рабочее дерево (отслеживаемые и новые файлы) + индекс + вся история Git
#   scripts/secret-scan.sh --no-history — без истории (быстро)
# Вывод: строки с находками (значения маскируются) и итог «N findings». Код возврата 1, если N > 0.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

HISTORY=1
[ "${1:-}" = "--no-history" ] && HISTORY=0

# Ключи провайдеров.
KEY_PATTERNS=(
  'AIza[0-9A-Za-z_-]{35}'              # Google / Gemini
  'sk-ant-[A-Za-z0-9_-]{20,}'          # Anthropic
  'sk-[A-Za-z0-9]{32,}'                # DeepSeek / OpenAI-совместимые
)
# Личные данные: email и телефоны. Разрешены вне проверки: profile.example/, evals/ (синтетика) и этот скрипт.
EMAIL_PATTERN='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
PHONE_PATTERN='(\+[0-9]{1,3}[ -]?\(?[0-9]{2,3}\)?[ -]?[0-9]{3}[ -]?[0-9]{2}[ -]?[0-9]{2})|(\(?[0-9]{3}\)?[ -][0-9]{3}[ -][0-9]{2}[ -][0-9]{2})'
# Безопасные адреса (документация, примеры).
EMAIL_ALLOW='@(example\.(com|org|net)|users\.noreply\.github\.com|anthropic\.com)$'
PII_EXCLUDE=(':(exclude)profile.example/**' ':(exclude)evals/**' ':(exclude)scripts/secret-scan.sh')

findings=0
mask() { sed -E 's/(AIza|sk-ant-|sk-)[A-Za-z0-9_-]{4}[A-Za-z0-9_-]*/\1****[masked]/g'; }

report() { # $1 — категория, stdin — строки git grep. Вызывать через `< <(…)`, не через `|`, иначе счётчик теряется.
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    echo "[$1] $(printf '%s' "$line" | cut -c1-200 | mask)"
    findings=$((findings + 1))
  done
}

# git grep: опции идут до шаблона, ревизии — после. $1 — режим: worktree | index | history.
ggrep() {
  local mode="$1" pattern="$2"; shift 2
  case "$mode" in
    worktree) git grep -I -n --untracked ${GREP_EXTRA[@]+"${GREP_EXTRA[@]}"} -E "$pattern" -- "$@" ;;
    index)    git grep -I -n --cached ${GREP_EXTRA[@]+"${GREP_EXTRA[@]}"} -E "$pattern" -- "$@" ;;
    history)  git rev-list --all | while read -r rev; do
                git grep -I -n ${GREP_EXTRA[@]+"${GREP_EXTRA[@]}"} -E "$pattern" "$rev" -- "$@"
              done ;;
  esac 2>/dev/null || true
}

scan_tree() { # $1 — режим
  local mode="$1"
  GREP_EXTRA=()
  for p in "${KEY_PATTERNS[@]}"; do
    report "key:$mode" < <(ggrep "$mode" "$p" . ':(exclude)scripts/secret-scan.sh')
  done
  GREP_EXTRA=(-o)
  report "email:$mode" < <(ggrep "$mode" "$EMAIL_PATTERN" . "${PII_EXCLUDE[@]}" | grep -v -E "$EMAIL_ALLOW" || true)
  report "phone:$mode" < <(ggrep "$mode" "$PHONE_PATTERN" . "${PII_EXCLUDE[@]}")
  GREP_EXTRA=()
}

# 1. Рабочее дерево: отслеживаемые и неотслеживаемые (не игнорируемые) файлы.
scan_tree worktree
# 2. Индекс.
scan_tree index
# 3. История: каждый коммит всех веток.
[ "$HISTORY" = 1 ] && scan_tree history

# 4. Файлы, которые должны игнорироваться, но попали в индекс (profile/, модели, логи, .env…).
report "ignored-but-tracked" < <(git ls-files -ci --exclude-standard)
# 5. Запрещённые каталоги и типы файлов в индексе независимо от .gitignore.
report "forbidden-path" < <(git ls-files | grep -E '(^|/)(profile|sessions|models|logs)/|\.(gguf|bin|p12|cer|key|wav|log)$|(^|/)\.env' \
  | grep -v -E '^(profile\.example|evals/audio)/' || true)

echo "$findings findings"
[ "$findings" -eq 0 ]
