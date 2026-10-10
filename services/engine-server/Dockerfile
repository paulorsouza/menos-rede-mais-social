# Imagem do motor (feed + anúncios). O contexto do build é a raiz do
# repositório: docker build -f services/engine-server/Dockerfile .
#
# Pendente para o build reproduzível do plano: fixar as imagens base por
# digest e gerar o binário com Nix.
FROM rust:1-slim-bookworm AS build
WORKDIR /src
COPY services/ services/
COPY params/ params/
RUN cargo build --release --locked --manifest-path services/Cargo.toml -p engine-server

FROM debian:bookworm-slim
COPY --from=build /src/services/target/release/engine-server /usr/local/bin/engine-server
COPY params/ /app/params/
ENV PARAMS_DIR=/app/params PORT=7070
EXPOSE 7070
CMD ["engine-server"]
