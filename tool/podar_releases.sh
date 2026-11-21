#!/usr/bin/env bash
# Deja solo los últimos KEEP releases `v1.0.<n>` y borra el resto con gh.
# Uso: gh release list --json tagName,createdAt,isLatest,isDraft,isPrerelease --limit 200 | tool/podar_releases.sh
# Variables: KEEP (default 5), CURRENT_TAG (release recién creado, nunca se borra),
#            DRY_RUN=1 (solo imprime qué borraría). Nunca falla por un borrado que no salió.
set -u
KEEP="${KEEP:-5}"
CURRENT_TAG="${CURRENT_TAG:-}"

JSON="$(cat)"
# Candidatos: tags v1.0.N, no draft/prerelease, del más nuevo al más viejo.
# Se conservan los primeros KEEP; del resto se excluyen el Latest y el actual.
TAGS="$(printf '%s' "$JSON" | jq -r --argjson keep "$KEEP" --arg cur "$CURRENT_TAG" '
  [ .[] | select(.tagName | test("^v1\\.0\\.[0-9]+$")) | select(.isDraft | not) | select(.isPrerelease | not) ]
  | sort_by(.createdAt) | reverse
  | .[$keep:]
  | .[] | select((.isLatest | not) and .tagName != $cur)
  | .tagName')"

if [ -z "$TAGS" ]; then
  echo "Nada para borrar (se conservan hasta $KEEP releases)."
  exit 0
fi

for tag in $TAGS; do
  if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "[dry-run] borraría $tag"
  elif gh release delete "$tag" --cleanup-tag --yes; then
    echo "Borrado $tag"
  else
    echo "::warning::No se pudo borrar $tag; sigo con el resto."
  fi
done
exit 0
