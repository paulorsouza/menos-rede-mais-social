# Serviço de legendas automáticas: o servidor HTTP do whisper.cpp, compilado
# numa versão fixa. Só o servidor entra na imagem; o modelo é baixado na
# primeira subida e fica num volume (ver iniciar.sh).
FROM debian:13-slim AS build

RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential cmake git ca-certificates \
  && rm -rf /var/lib/apt/lists/*

ARG WHISPER_VERSION=v1.9.4
RUN git clone --depth 1 --branch "$WHISPER_VERSION" https://github.com/ggml-org/whisper.cpp /src

WORKDIR /src
RUN cmake -B build -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DWHISPER_BUILD_TESTS=OFF \
  && cmake --build build -j --target whisper-server

FROM debian:13-slim

RUN apt-get update \
  && apt-get install -y --no-install-recommends curl ca-certificates libgomp1 \
  && rm -rf /var/lib/apt/lists/*

COPY --from=build /src/build/bin/whisper-server /usr/local/bin/whisper-server
COPY iniciar.sh /iniciar.sh

EXPOSE 8080
ENTRYPOINT ["sh", "/iniciar.sh"]
