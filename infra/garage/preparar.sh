#!/bin/sh
# Prepara o Garage da demonstração: monta o cluster de um nó, cria a chave do
# backend e o balde público "midia", servido pelo endpoint web para a borda.
# Pode rodar quantas vezes for preciso: o que já existe fica como está.
set -eu

API="${GARAGE_ADMIN_URL:-http://garage:3903}/v2"
AUTH="Authorization: Bearer $GARAGE_ADMIN_TOKEN"

call() {
  if [ $# -ge 3 ]; then
    curl -sS -f -X "$1" -H "$AUTH" -H "Content-Type: application/json" -d "$3" "$API/$2"
  else
    curl -sS -f -X "$1" -H "$AUTH" "$API/$2"
  fi
}

until call GET GetClusterHealth >/dev/null 2>&1; do sleep 1; done

if call GET GetClusterLayout | grep -q '"roles": \[\]'; then
  node=$(call GET GetClusterStatus | sed -n 's/.*"id": "\([0-9a-f]\{64\}\)".*/\1/p' | head -n 1)
  call POST UpdateClusterLayout \
    "{\"roles\":[{\"id\":\"$node\",\"zone\":\"demo\",\"capacity\":10000000000,\"tags\":[]}]}" >/dev/null
  call POST ApplyClusterLayout '{"version":1}' >/dev/null
  echo "garage: cluster de um nó montado"
fi

call POST ImportKey \
  "{\"accessKeyId\":\"$S3_ACCESS_KEY_ID\",\"secretAccessKey\":\"$S3_SECRET_ACCESS_KEY\",\"name\":\"backend\"}" \
  >/dev/null 2>&1 && echo "garage: chave do backend criada" || true

call POST CreateBucket "{\"globalAlias\":\"$S3_BUCKET\"}" >/dev/null 2>&1 &&
  echo "garage: balde $S3_BUCKET criado" || true

bucket=$(call GET "GetBucketInfo?globalAlias=$S3_BUCKET" | sed -n 's/^  "id": "\([0-9a-f]*\)".*/\1/p')

call POST "UpdateBucket?id=$bucket" \
  '{"websiteAccess":{"enabled":true,"indexDocument":"index.html"}}' >/dev/null
call POST AllowBucketKey \
  "{\"bucketId\":\"$bucket\",\"accessKeyId\":\"$S3_ACCESS_KEY_ID\",\"permissions\":{\"read\":true,\"write\":true,\"owner\":true}}" \
  >/dev/null

echo "garage: pronto"
