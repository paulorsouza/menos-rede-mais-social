//! Servidor HTTP dos motores da -rede+social.
//!
//! Expõe o motor de feed, o de anúncios e o cofre do CPF para o backend, com
//! os mesmos campos dos contratos em `proto/`. Por enquanto a conversa é em JSON; o gRPC entra
//! quando os dois lados estiverem estáveis.

use std::{collections::BTreeMap, fs, path::Path, sync::Arc};

use axum::{
    Json, Router,
    extract::State,
    http::StatusCode,
    routing::{get, post},
};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

pub const ENGINE_VERSION: &str = env!("CARGO_PKG_VERSION");

/// Commit do build oficial. Em desenvolvimento, aparece como "dev".
pub const ENGINE_BUILD: &str = match option_env!("GIT_SHA") {
    Some(sha) => sha,
    None => "dev",
};

/// Um arquivo de parâmetros exatamente como foi lido do disco. O hash permite
/// a qualquer pessoa conferir que é o mesmo arquivo publicado no repositório.
#[derive(Debug, Clone, Serialize)]
pub struct LoadedFile {
    pub path: String,
    pub version: u32,
    pub sha256: String,
    pub source: String,
}

pub struct Engines {
    pub feed: feed_engine::Params,
    pub ads: ads_engine::Params,
    pub guardians: cofre::Guardians,
    pub feed_file: LoadedFile,
    pub ads_file: LoadedFile,
    pub guardians_file: LoadedFile,
    /// Chave que assina os recibos do feed. Nasce quando o motor sobe e não
    /// sai da memória; a parte pública vai para o registro público. Numa
    /// máquina atestada, ela fica presa ao binário que está rodando.
    pub receipt_key: ed25519_dalek::SigningKey,
    /// Só na demonstração: as fatias dos guardiões de teste, para simular uma
    /// ordem judicial sem as cinco instituições. Em produção fica vazio.
    pub demo_shares: Vec<cofre::Share>,
}

impl Engines {
    pub fn load(params_dir: &Path) -> Result<Self, String> {
        let feed_source = read(params_dir, "feed.toml")?;
        let ads_source = read(params_dir, "ads.toml")?;
        let guardians_source = read(params_dir, "guardioes.toml")?;

        let feed = feed_engine::Params::from_toml_str(&feed_source)
            .map_err(|error| format!("params/feed.toml: {error}"))?;
        let ads = ads_engine::Params::from_toml_str(&ads_source)
            .map_err(|error| format!("params/ads.toml: {error}"))?;
        let guardians = cofre::Guardians::from_toml_str(&guardians_source)
            .map_err(|error| format!("params/guardioes.toml: {error}"))?;
        Ok(Self {
            feed_file: loaded("params/feed.toml", feed.version, feed_source),
            ads_file: loaded("params/ads.toml", ads.version, ads_source),
            guardians_file: loaded("params/guardioes.toml", guardians.version, guardians_source),
            feed,
            ads,
            guardians,
            demo_shares: Vec::new(),
            receipt_key: ed25519_dalek::SigningKey::generate(&mut rand_core::OsRng),
        })
    }

    /// Carrega as fatias de demonstração de uma pasta (fatia-N.json). Recusa
    /// fatias que não batem com a chave de conferência publicada.
    pub fn with_demo_shares(mut self, dir: &Path) -> Result<Self, String> {
        for index in self.guardians.members.keys() {
            let path = dir.join(format!("fatia-{index}.json"));
            let text = fs::read_to_string(&path).map_err(|e| format!("{}: {e}", path.display()))?;
            let file: cofre::ShareFile =
                serde_json::from_str(&text).map_err(|e| format!("{}: {e}", path.display()))?;
            let share = cofre::Share::from_file(&file).map_err(|e| e.to_string())?;

            // Uma parte qualquer prova se a fatia é a publicada.
            let probe = cofre::seal(&self.guardians.public_key, b"teste", b"teste");
            cofre::partial(&share, &probe, b"teste")
                .and_then(|partial| cofre::verify_partial(&self.guardians, &probe, &partial))
                .map_err(|_| format!("{} não é a fatia publicada", path.display()))?;
            self.demo_shares.push(share);
        }
        Ok(self)
    }
}

fn read(dir: &Path, name: &str) -> Result<String, String> {
    let path = dir.join(name);
    fs::read_to_string(&path).map_err(|error| format!("{}: {error}", path.display()))
}

fn loaded(path: &str, version: u32, source: String) -> LoadedFile {
    LoadedFile {
        path: path.to_string(),
        version,
        sha256: format!("{:x}", Sha256::digest(source.as_bytes())),
        source,
    }
}

pub fn router(engines: Arc<Engines>) -> Router {
    Router::new()
        .route("/health", get(health))
        .route("/transparency", get(transparency))
        .route("/feed/rank", post(rank))
        .route("/ads/payout", post(payout))
        .route("/ads/impressions", post(impressions))
        .route("/ads/split-shorts", post(split_shorts))
        .route("/ads/quote", post(quote))
        .route("/ads/pick", post(pick))
        .route("/ads/close-month", post(close_month))
        .route("/vault/seal", post(vault_seal))
        .route("/vault/verify", post(vault_verify))
        .route("/vault/open", post(vault_open))
        .route("/vault/demo-partial", post(vault_demo_partial))
        .with_state(engines)
}

type Shared = State<Arc<Engines>>;
type ApiError = (StatusCode, String);

async fn health() -> Json<serde_json::Value> {
    Json(serde_json::json!({ "status": "ok" }))
}

#[derive(Serialize)]
struct Transparency {
    engine_version: &'static str,
    engine_build: &'static str,
    feed_params: LoadedFile,
    ads_params: LoadedFile,
    guardians_params: LoadedFile,
    receipt_public_key: String,
    feed_settings: feed_engine::Params,
    payout_bands: Vec<ads_engine::PayoutBand>,
    shorts_ad_every: u32,
    ads_settings: ads_engine::Params,
}

async fn transparency(State(engines): Shared) -> Json<Transparency> {
    Json(Transparency {
        engine_version: ENGINE_VERSION,
        engine_build: ENGINE_BUILD,
        feed_params: engines.feed_file.clone(),
        ads_params: engines.ads_file.clone(),
        guardians_params: engines.guardians_file.clone(),
        receipt_public_key: engines.receipt_public_key(),
        feed_settings: engines.feed.clone(),
        payout_bands: engines.ads.payout_bands.clone(),
        shorts_ad_every: engines.ads.shorts_ad_every,
        ads_settings: engines.ads.clone(),
    })
}

#[derive(Serialize)]
struct RankResponse {
    items: Vec<feed_engine::RankedItem>,
    engine_version: &'static str,
    engine_build: &'static str,
    params_version: u32,
    params_sha256: String,
    receipt: feed_engine::receipt::Receipt,
}

async fn rank(
    State(engines): Shared,
    Json(input): Json<feed_engine::receipt::RankInput>,
) -> Json<RankResponse> {
    let items = feed_engine::rank(
        input.mode,
        &input.viewer,
        &input.candidates,
        &input.edges,
        &engines.feed,
        input.now,
    );
    let receipt = engines.sign_receipt(&input, &items);

    Json(RankResponse {
        items,
        engine_version: ENGINE_VERSION,
        engine_build: ENGINE_BUILD,
        params_version: engines.feed.version,
        params_sha256: engines.feed_file.sha256.clone(),
        receipt,
    })
}

impl Engines {
    pub fn receipt_public_key(&self) -> String {
        use base64::Engine as _;
        base64::engine::general_purpose::STANDARD
            .encode(self.receipt_key.verifying_key().to_bytes())
    }

    /// Assina o recibo de um cálculo de feed.
    pub fn sign_receipt(
        &self,
        input: &feed_engine::receipt::RankInput,
        items: &[feed_engine::RankedItem],
    ) -> feed_engine::receipt::Receipt {
        use base64::Engine as _;
        use ed25519_dalek::Signer;

        let mut receipt = feed_engine::receipt::Receipt {
            input_sha256: input.sha256(),
            output_sha256: feed_engine::receipt::output_sha256(items),
            params_sha256: self.feed_file.sha256.clone(),
            engine_version: ENGINE_VERSION.to_string(),
            engine_build: ENGINE_BUILD.to_string(),
            now: input.now,
            signature: String::new(),
        };
        let signature = self.receipt_key.sign(receipt.signed_message().as_bytes());
        receipt.signature = base64::engine::general_purpose::STANDARD.encode(signature.to_bytes());
        receipt
    }
}

#[derive(Deserialize)]
struct PayoutRequest {
    views: u64,
    /// Sem ele, vale o valor base de params/ads.toml.
    #[serde(default)]
    cents_per_thousand: Option<u64>,
}

#[derive(Serialize)]
struct PayoutResponse {
    effective_views: u64,
    payout_cents: u64,
    params_version: u32,
}

async fn payout(
    State(engines): Shared,
    Json(request): Json<PayoutRequest>,
) -> Json<PayoutResponse> {
    let bands = &engines.ads.payout_bands;

    Json(PayoutResponse {
        effective_views: ads_engine::effective_views(request.views, bands),
        payout_cents: ads_engine::monthly_payout_cents(
            request.views,
            request
                .cents_per_thousand
                .unwrap_or(engines.ads.payout.base_cents_per_thousand),
            bands,
        ),
        params_version: engines.ads.version,
    })
}

#[derive(Deserialize)]
struct ImpressionsRequest {
    hours_per_day: u64,
    ad_seconds: u64,
}

#[derive(Serialize)]
struct ImpressionsResponse {
    impressions: u64,
}

async fn impressions(
    Json(request): Json<ImpressionsRequest>,
) -> Result<Json<ImpressionsResponse>, ApiError> {
    if request.ad_seconds == 0 {
        return Err((
            StatusCode::BAD_REQUEST,
            "ad_seconds precisa ser maior que zero".into(),
        ));
    }
    if request.hours_per_day > u64::MAX / 3600 {
        return Err((
            StatusCode::BAD_REQUEST,
            "hours_per_day grande demais".into(),
        ));
    }

    Ok(Json(ImpressionsResponse {
        impressions: ads_engine::impressions_per_day(request.hours_per_day, request.ad_seconds),
    }))
}

#[derive(Deserialize)]
struct SplitRequest {
    revenue_cents: u64,
    views: Vec<ads_engine::ShortView>,
}

#[derive(Serialize)]
struct SplitResponse {
    /// A parte dos criadores, dividida pelo tempo assistido.
    cents_by_creator: BTreeMap<u64, u64>,
    /// O que fica para o fundo de infraestrutura.
    fund_cents: u64,
}

/// Rateio de um anúncio de shorts: a parte dos criadores
/// (`creator_share_percent`) é dividida pelo tempo assistido; o resto, e o que
/// ninguém pôde receber, fica com o fundo.
async fn split_shorts(
    State(engines): Shared,
    Json(request): Json<SplitRequest>,
) -> Json<SplitResponse> {
    let pool = ads_engine::closing::shorts_creator_pool(request.revenue_cents, &engines.ads);
    let cents_by_creator =
        ads_engine::split_shorts_revenue(pool, &request.views, engines.ads.payout.shorts_split);
    let paid: u64 = cents_by_creator.values().sum();

    Json(SplitResponse {
        cents_by_creator,
        fund_cents: request.revenue_cents - paid,
    })
}

#[derive(Deserialize)]
struct QuoteRequest {
    hours_per_day: u64,
    days: u64,
    regional: bool,
}

async fn quote(
    State(engines): Shared,
    Json(request): Json<QuoteRequest>,
) -> Result<Json<ads_engine::Quote>, ApiError> {
    if request.hours_per_day == 0
        || request.hours_per_day > 24 * 1000
        || request.days == 0
        || request.days > 366
    {
        return Err((
            StatusCode::BAD_REQUEST,
            "horas por dia ou dias fora do limite".into(),
        ));
    }
    Ok(Json(ads_engine::quote(
        request.hours_per_day,
        request.days,
        request.regional,
        &engines.ads,
    )))
}

#[derive(Deserialize)]
struct PickRequest {
    viewer_region: String,
    seconds_into_day: u32,
    audience: ads_engine::pacing::Audience,
    candidates: Vec<ads_engine::pacing::Candidate>,
    slots: usize,
}

#[derive(Serialize)]
struct PickResponse {
    campaigns: Vec<u64>,
}

async fn pick(State(engines): Shared, Json(request): Json<PickRequest>) -> Json<PickResponse> {
    Json(PickResponse {
        campaigns: ads_engine::pacing::pick(
            &request.viewer_region,
            request.seconds_into_day,
            request.audience,
            &request.candidates,
            &engines.ads.delivery,
            request.slots.min(100),
        ),
    })
}

#[derive(Deserialize)]
struct CloseMonthRequest {
    creators: Vec<ads_engine::closing::CreatorMonth>,
}

#[derive(Serialize)]
struct CloseMonthResponse {
    results: Vec<ads_engine::closing::CreatorResult>,
    params_version: u32,
    params_sha256: String,
    engine_version: &'static str,
    engine_build: &'static str,
}

/// Fecha o mês: a conta de cada criador, feita só com os dados dele.
async fn close_month(
    State(engines): Shared,
    Json(request): Json<CloseMonthRequest>,
) -> Json<CloseMonthResponse> {
    Json(CloseMonthResponse {
        results: request
            .creators
            .iter()
            .map(|month| ads_engine::closing::close(month, &engines.ads))
            .collect(),
        params_version: engines.ads.version,
        params_sha256: engines.ads_file.sha256.clone(),
        engine_version: ENGINE_VERSION,
        engine_build: ENGINE_BUILD,
    })
}

// ---------------------------------------------------------------------------
// Cofre do CPF. Selar usa só a chave pública dos guardiões; abrir exige as
// partes de pelo menos `threshold` deles, cada uma com a sua prova.

#[derive(Deserialize)]
struct SealRequest {
    plaintext: String,
    context: String,
}

#[derive(Serialize)]
struct SealResponse {
    sealed: String,
    guardians_version: u32,
}

async fn vault_seal(
    State(engines): Shared,
    Json(request): Json<SealRequest>,
) -> Json<SealResponse> {
    let sealed = cofre::seal(
        &engines.guardians.public_key,
        request.plaintext.as_bytes(),
        request.context.as_bytes(),
    );
    Json(SealResponse {
        sealed: sealed.to_base64(),
        guardians_version: engines.guardians.version,
    })
}

#[derive(Deserialize)]
struct VerifyRequest {
    sealed: String,
    partial: cofre::PartialWire,
}

#[derive(Serialize)]
struct VerifyResponse {
    valid: bool,
}

async fn vault_verify(
    State(engines): Shared,
    Json(request): Json<VerifyRequest>,
) -> Result<Json<VerifyResponse>, ApiError> {
    let sealed = cofre::Sealed::from_base64(&request.sealed).map_err(bad_request)?;
    let valid = cofre::Partial::try_from(&request.partial)
        .and_then(|partial| cofre::verify_partial(&engines.guardians, &sealed, &partial))
        .is_ok();
    Ok(Json(VerifyResponse { valid }))
}

#[derive(Deserialize)]
struct OpenRequest {
    sealed: String,
    context: String,
    partials: Vec<cofre::PartialWire>,
}

#[derive(Serialize)]
struct OpenResponse {
    plaintext: String,
}

async fn vault_open(
    State(engines): Shared,
    Json(request): Json<OpenRequest>,
) -> Result<Json<OpenResponse>, ApiError> {
    let sealed = cofre::Sealed::from_base64(&request.sealed).map_err(bad_request)?;
    let partials = request
        .partials
        .iter()
        .map(cofre::Partial::try_from)
        .collect::<Result<Vec<_>, _>>()
        .map_err(bad_request)?;
    let plaintext = cofre::open(
        &engines.guardians,
        &sealed,
        &partials,
        request.context.as_bytes(),
    )
    .map_err(|error| (StatusCode::UNPROCESSABLE_ENTITY, error.to_string()))?;
    Ok(Json(OpenResponse {
        plaintext: String::from_utf8_lossy(&plaintext).into_owned(),
    }))
}

#[derive(Deserialize)]
struct DemoPartialRequest {
    index: u8,
    sealed: String,
    /// O contexto que está no pedido: o guardião confere o selado com ele.
    context: String,
}

async fn vault_demo_partial(
    State(engines): Shared,
    Json(request): Json<DemoPartialRequest>,
) -> Result<Json<cofre::PartialWire>, ApiError> {
    let share = engines
        .demo_shares
        .iter()
        .find(|share| share.index == request.index)
        .ok_or((
            StatusCode::NOT_FOUND,
            "sem fatias de demonstração para este guardião".to_string(),
        ))?;
    let sealed = cofre::Sealed::from_base64(&request.sealed).map_err(bad_request)?;
    let partial =
        cofre::partial(share, &sealed, request.context.as_bytes()).map_err(bad_request)?;
    Ok(Json(cofre::PartialWire::from(&partial)))
}

fn bad_request(error: cofre::Error) -> ApiError {
    (StatusCode::BAD_REQUEST, error.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::{body::Body, http::Request};
    use http_body_util::BodyExt;
    use serde_json::{Value, json};
    use tower::ServiceExt;

    fn params_dir() -> std::path::PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR")).join("../../params")
    }

    async fn call(method: &str, uri: &str, body: Value) -> (StatusCode, Value) {
        let app = router(Arc::new(Engines::load(&params_dir()).unwrap()));
        let request = Request::builder()
            .method(method)
            .uri(uri)
            .header("content-type", "application/json")
            .body(Body::from(body.to_string()))
            .unwrap();

        let response = app.oneshot(request).await.unwrap();
        let status = response.status();
        let bytes = response.into_body().collect().await.unwrap().to_bytes();
        (
            status,
            serde_json::from_slice(&bytes).unwrap_or(Value::Null),
        )
    }

    async fn call_with_demo(uri: &str, body: Value) -> (StatusCode, Value) {
        let demo = Path::new(env!("CARGO_MANIFEST_DIR")).join("../cofre/demo");
        let engines = Engines::load(&params_dir())
            .unwrap()
            .with_demo_shares(&demo)
            .unwrap();
        let request = Request::builder()
            .method("POST")
            .uri(uri)
            .header("content-type", "application/json")
            .body(Body::from(body.to_string()))
            .unwrap();
        let response = router(Arc::new(engines)).oneshot(request).await.unwrap();
        let status = response.status();
        let bytes = response.into_body().collect().await.unwrap().to_bytes();
        (
            status,
            serde_json::from_slice(&bytes).unwrap_or(Value::Null),
        )
    }

    #[tokio::test]
    async fn vault_opens_only_with_three_guardians() {
        let (_, sealed) = call(
            "POST",
            "/vault/seal",
            json!({ "plaintext": "52998224725", "context": "cpf:conta-1" }),
        )
        .await;
        let sealed = sealed["sealed"].as_str().unwrap().to_string();

        let mut partials = Vec::new();
        for index in [1, 3, 5] {
            let (status, partial) = call_with_demo(
                "/vault/demo-partial",
                json!({ "index": index, "sealed": sealed, "context": "cpf:conta-1" }),
            )
            .await;
            assert_eq!(status, StatusCode::OK);
            let (_, check) = call(
                "POST",
                "/vault/verify",
                json!({ "sealed": sealed, "partial": partial }),
            )
            .await;
            assert_eq!(check["valid"], true);
            partials.push(partial);
        }

        let (status, _) = call(
            "POST",
            "/vault/open",
            json!({ "sealed": sealed, "context": "cpf:conta-1", "partials": &partials[..2] }),
        )
        .await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

        let (status, opened) = call(
            "POST",
            "/vault/open",
            json!({ "sealed": sealed, "context": "cpf:conta-1", "partials": partials }),
        )
        .await;
        assert_eq!(status, StatusCode::OK);
        assert_eq!(opened["plaintext"], "52998224725");

        // O guardião não calcula a parte com o contexto de outra conta.
        let (status, _) = call_with_demo(
            "/vault/demo-partial",
            json!({ "index": 1, "sealed": sealed, "context": "cpf:conta-2" }),
        )
        .await;
        assert_eq!(status, StatusCode::BAD_REQUEST);
    }

    #[tokio::test]
    async fn without_demo_shares_there_is_no_shortcut() {
        let (_, sealed) = call(
            "POST",
            "/vault/seal",
            json!({ "plaintext": "x", "context": "y" }),
        )
        .await;
        let (status, _) = call(
            "POST",
            "/vault/demo-partial",
            json!({ "index": 1, "sealed": sealed["sealed"], "context": "y" }),
        )
        .await;
        assert_eq!(status, StatusCode::NOT_FOUND);
    }

    #[tokio::test]
    async fn transparency_shows_the_hash_of_the_file_in_use() {
        let source = fs::read(params_dir().join("feed.toml")).unwrap();
        let expected = format!("{:x}", Sha256::digest(&source));

        let (status, body) = call("GET", "/transparency", Value::Null).await;

        assert_eq!(status, StatusCode::OK);
        assert_eq!(body["feed_params"]["sha256"], expected);
        assert_eq!(body["feed_params"]["path"], "params/feed.toml");
        assert_eq!(body["shorts_ad_every"], 6);
        assert_eq!(body["feed_settings"]["neighbors"]["min_shared"], 2);
    }

    #[tokio::test]
    async fn bubble_follows_the_graph() {
        // Eu (9) e a pessoa 3 curtimos os posts 50 e 51. Ela também curtiu o 52.
        let like = |user: u64, post: u64| json!({ "user_id": user, "post_id": post, "kind": "like", "at": 250 });
        let (status, body) = call(
            "POST",
            "/feed/rank",
            json!({
                "mode": "bubble",
                "viewer": { "id": 9, "follows": [] },
                "candidates": [
                    { "post_id": 52, "author_id": 4, "created_at": 200, "likes": 1, "saves": 0 },
                    { "post_id": 53, "author_id": 4, "created_at": 200, "likes": 0, "saves": 0 }
                ],
                "edges": [like(9, 50), like(9, 51), like(3, 50), like(3, 51), like(3, 52)],
                "now": 300
            }),
        )
        .await;

        assert_eq!(status, StatusCode::OK);
        assert_eq!(body["items"].as_array().unwrap().len(), 1);
        assert_eq!(body["items"][0]["post_id"], 52);
        assert_eq!(
            body["items"][0]["reasons"][0],
            json!({ "kind": "similar_engaged", "value": 1 })
        );
    }

    #[tokio::test]
    async fn rank_returns_items_with_reasons() {
        let (status, body) = call(
            "POST",
            "/feed/rank",
            json!({
                "mode": "chronological",
                "viewer": { "id": 9, "follows": [1] },
                "candidates": [
                    { "post_id": 10, "author_id": 1, "created_at": 100, "likes": 0, "saves": 0 },
                    { "post_id": 11, "author_id": 2, "created_at": 200, "likes": 0, "saves": 0 }
                ],
                "now": 300
            }),
        )
        .await;

        assert_eq!(status, StatusCode::OK);
        assert_eq!(body["items"].as_array().unwrap().len(), 1);
        assert_eq!(body["items"][0]["post_id"], 10);
        assert_eq!(body["items"][0]["reasons"][0]["kind"], "you_follow");
        assert_eq!(body["params_version"], 2);
        assert_eq!(body["receipt"]["params_sha256"], body["params_sha256"]);
        assert!(body["receipt"]["signature"].as_str().unwrap().len() > 80);
    }

    #[tokio::test]
    async fn payout_matches_plan_example() {
        let (status, body) = call(
            "POST",
            "/ads/payout",
            json!({ "views": 2_000_000, "cents_per_thousand": 200 }),
        )
        .await;

        assert_eq!(status, StatusCode::OK);
        assert_eq!(body["effective_views"], 1_275_000);
        assert_eq!(body["payout_cents"], 255_000);
    }

    #[tokio::test]
    async fn impressions_reject_zero_length_ads() {
        let (status, _) = call(
            "POST",
            "/ads/impressions",
            json!({ "hours_per_day": 10, "ad_seconds": 0 }),
        )
        .await;

        assert_eq!(status, StatusCode::BAD_REQUEST);
    }

    #[tokio::test]
    async fn split_shorts_gives_equal_parts() {
        let (status, body) = call(
            "POST",
            "/ads/split-shorts",
            json!({
                "revenue_cents": 1000,
                "views": [
                    { "creator_id": 1, "watched_ms": 70000, "monetized": true },
                    { "creator_id": 2, "watched_ms": 30000, "monetized": true }
                ]
            }),
        )
        .await;

        // 55% para os criadores (params/ads.toml), em partes iguais por
        // short, seja qual for o tempo assistido.
        assert_eq!(status, StatusCode::OK);
        assert_eq!(body["cents_by_creator"], json!({ "1": 275, "2": 275 }));
        assert_eq!(body["fund_cents"], 450);
    }

    #[tokio::test]
    async fn closing_a_month_returns_the_lines_to_publish() {
        let (status, body) = call(
            "POST",
            "/ads/close-month",
            json!({ "creators": [{
                "month": "2026-10",
                "creator": "criadora",
                "video_views": [
                    { "viewer": "a", "post": 1, "campaign": 1, "regional": false, "at": 1791655200, "viewer_verified": true },
                    { "viewer": "a", "post": 1, "campaign": 1, "regional": false, "at": 1791655260, "viewer_verified": true }
                ]
            }]}),
        )
        .await;

        assert_eq!(status, StatusCode::OK);
        let result = &body["results"][0];
        assert_eq!(result["statuses"], json!(["counted", "repeated_same_day"]));
        assert_eq!(result["leaves"].as_array().unwrap().len(), 3);
        assert_eq!(body["params_version"], 3);
    }

    #[tokio::test]
    async fn pick_spreads_the_day_budget() {
        let (status, body) = call(
            "POST",
            "/ads/pick",
            json!({
                "viewer_region": "Campinas/SP",
                "seconds_into_day": 43200,
                "audience": { "region": 1, "total": 1 },
                "candidates": [
                    { "id": 1, "scope": "national", "daily_budget": 1000, "delivered_today": 999, "delivered_in_region_today": 0 },
                    { "id": 2, "scope": "regional", "region": "Campinas/SP", "daily_budget": 1000, "delivered_today": 0, "delivered_in_region_today": 0 }
                ],
                "slots": 2
            }),
        )
        .await;

        assert_eq!(status, StatusCode::OK);
        assert_eq!(body["campaigns"], json!([2, 2]));
    }
}
