#!/bin/sh
# Baixa o modelo na primeira vez e sobe o servidor de transcrição.
#
# MODELO=small (466 MB) é o padrão: no português ele erra pouco, e o base
# (142 MB), mais rápido, troca palavras demais para servir de legenda.
# MODELO=medium (1,5 GB) acerta mais e é bem mais lento no processador.
set -eu

modelo="${MODELO:-small}"
arquivo="/modelos/ggml-$modelo.bin"

if [ ! -s "$arquivo" ]; then
  echo "legendas: baixando o modelo $modelo, só na primeira vez"
  curl -fsSL --retry 3 -o "$arquivo.parcial" \
    "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-$modelo.bin"
  mv "$arquivo.parcial" "$arquivo"
fi

exec whisper-server -m "$arquivo" --host 0.0.0.0 --port 8080 -l "${IDIOMA:-pt}" -t "$(nproc)"
