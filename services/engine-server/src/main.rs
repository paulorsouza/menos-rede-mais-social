use std::{env, net::SocketAddr, path::PathBuf, process, sync::Arc};

use engine_server::{ENGINE_BUILD, ENGINE_VERSION, Engines, router};

#[tokio::main]
async fn main() {
    // Rodando com `cargo run` dentro de services/, os parâmetros ficam em ../params.
    let params_dir = PathBuf::from(env::var("PARAMS_DIR").unwrap_or_else(|_| "../params".into()));
    let port = env::var("PORT")
        .ok()
        .and_then(|value| value.parse().ok())
        .unwrap_or(7070);

    let mut engines = Engines::load(&params_dir).unwrap_or_else(|error| {
        eprintln!("não consegui carregar os parâmetros: {error}");
        process::exit(1);
    });

    // Só na demonstração. Em produção as fatias ficam com os guardiões.
    if let Ok(dir) = env::var("COFRE_DEMO_FATIAS") {
        engines = engines
            .with_demo_shares(&PathBuf::from(&dir))
            .unwrap_or_else(|error| {
                eprintln!("fatias de demonstração: {error}");
                process::exit(1);
            });
        eprintln!("cofre: fatias de DEMONSTRAÇÃO carregadas de {dir}");
    }

    eprintln!(
        "motor {ENGINE_VERSION} ({ENGINE_BUILD}) · feed v{} sha256 {} · ads v{} sha256 {}",
        engines.feed.version,
        engines.feed_file.sha256,
        engines.ads.version,
        engines.ads_file.sha256
    );

    let address = SocketAddr::from(([0, 0, 0, 0], port));
    let listener = tokio::net::TcpListener::bind(address)
        .await
        .unwrap_or_else(|error| {
            eprintln!("não consegui abrir a porta {port}: {error}");
            process::exit(1);
        });

    eprintln!("ouvindo em http://{address}");
    axum::serve(listener, router(Arc::new(engines)))
        .await
        .expect("o servidor parou com erro");
}
