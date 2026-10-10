//! Verificador aberto da -rede+social.
//!
//! Não fala com a rede: você baixa os arquivos (com o navegador ou com curl)
//! e ele confere tudo localmente, com o mesmo código que roda no motor.
//!
//! verificador feed <conta-do-feed.json> --parametros <params/feed.toml> [--chave <base64>]
//!                  [--registro <entradas.json> [--cabecalho <registro.json>]]
//!     Refaz o cálculo do seu feed, confere o recibo assinado pelo motor e
//!     confere que cada curtida, view e seguidor usado estava no último
//!     retrato do grafo, ou é mais novo que ele. Com --registro, confere
//!     também que a raiz e a hora desse retrato foram publicadas no registro
//!     público e que a chave do recibo é a de uma versão publicada do motor.
//!     Com --cabecalho, confere que as entradas são as do cabeçalho assinado.
//!     Baixe a conta em "Baixar a conta deste feed", no chip do motor.
//!
//!     Limite: a conta prova as ligações usadas, não os números de cada post
//!     candidato (curtidas, salvamentos, data e autor) nem que nenhuma
//!     ligação ficou de fora. Isso pede que o retrato comprometa também os
//!     posts e a lista completa de ligações de cada pessoa.
//!
//! verificador registro <registro.json> <entradas.json> [--chave <base64>]
//!                      [--anterior <registro-antigo.json> --consistencia <prova.json>]
//!     Confere a assinatura do cabeçalho, recalcula a raiz a partir das
//!     entradas publicadas e, se você guardou um cabeçalho antigo, prova que
//!     nada do que estava nele foi trocado ou apagado.
//!     registro.json:   GET /api/registro
//!     entradas.json:   GET /api/registro/entradas
//!     prova.json:      GET /api/registro/consistencia?de=<tamanho antigo>
//!
//! verificador pagamento <extrato.json> --parametros <params/ads.toml>
//!                       [--registro <entradas.json> [--cabecalho <registro.json>]]
//!     Refaz o fechamento do seu mês com o mesmo código do motor de anúncios:
//!     quais views com anúncio contaram, as faixas, a sua parte de cada
//!     anúncio dos shorts e o total. Confere que cada linha do extrato está na
//!     árvore do fechamento e, com --registro, que a raiz dela foi publicada.
//!     Baixe o extrato em "Extrato", no painel do criador.

use std::{collections::BTreeMap, env, fs, process};

use base64::{Engine as _, engine::general_purpose::STANDARD as B64};
use feed_engine::receipt::{RankInput, Receipt, output_sha256};
use feed_engine::{EdgeKind, Params, RankedItem};
use registro::{Hash, TreeHead, leaf_hash, parse_hash, root, verify_consistency, verify_inclusion};
use serde::Deserialize;
use serde_json::Value;
use sha2::{Digest, Sha256};

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    let result = match args.first().map(String::as_str) {
        Some("feed") => feed(&args[1..]),
        Some("registro") => registry(&args[1..]),
        Some("pagamento") => payment(&args[1..]),
        _ => Err(
            "uso: verificador feed | registro | pagamento (veja o começo de src/main.rs)".into(),
        ),
    };
    match result {
        Ok(true) => println!("\nTudo confere."),
        Ok(false) => {
            println!("\nAlguma coisa NÃO confere. Veja as linhas com ✗.");
            process::exit(1);
        }
        Err(message) => {
            eprintln!("{message}");
            process::exit(2);
        }
    }
}

/// Imprime o resultado de uma conferência e devolve se passou.
fn check(ok: bool, what: &str) -> bool {
    println!("{} {what}", if ok { "✓" } else { "✗" });
    ok
}

// ---------------------------------------------------------------------------
// Feed

#[derive(Deserialize)]
struct FeedAccount {
    entrada: RankInput,
    saida: Vec<RankedItem>,
    recibo: Receipt,
    chave_recibos: Option<String>,
    retrato: Option<SnapshotJson>,
    #[serde(default)]
    pseudonimos: BTreeMap<String, String>,
    provas: Option<ProofsJson>,
    recentes: Option<RecentJson>,
}

#[derive(Deserialize)]
struct SnapshotJson {
    id: u64,
    raiz: String,
    tamanho: u64,
    /// A hora do retrato, como foi publicada no registro.
    em: String,
}

#[derive(Deserialize)]
struct ProofsJson {
    ligacoes: Vec<EdgeProofJson>,
    seguindo: Vec<FollowProofJson>,
}

#[derive(Deserialize)]
struct EdgeProofJson {
    item: usize,
    folha: u64,
    caminho: Vec<String>,
}

#[derive(Deserialize)]
struct FollowProofJson {
    seguido: u64,
    desde: i64,
    folha: u64,
    caminho: Vec<String>,
}

#[derive(Deserialize)]
struct RecentJson {
    ligacoes: Vec<usize>,
    seguindo: Vec<RecentFollowJson>,
}

#[derive(Deserialize)]
struct RecentFollowJson {
    seguido: u64,
    desde: i64,
}

fn feed(args: &[String]) -> Result<bool, String> {
    let (flags, files) = flags(args)?;
    let path = files.first().ok_or("falta o arquivo da conta do feed")?;
    let account: FeedAccount = read_json(path)?;
    let params_path = flag(&flags, "--parametros")?;
    let params_bytes = fs::read(params_path).map_err(|e| format!("{params_path}: {e}"))?;
    let params = Params::from_toml_str(
        std::str::from_utf8(&params_bytes).map_err(|_| "parâmetros não são texto")?,
    )
    .map_err(|e| format!("{params_path}: {e}"))?;

    let mut ok = true;
    println!(
        "Recibo do motor {} ({})",
        account.recibo.engine_version, account.recibo.engine_build
    );

    ok &= check(
        account.entrada.sha256() == account.recibo.input_sha256,
        "a entrada do arquivo é a mesma que o motor assinou",
    );
    ok &= check(
        hex::encode(Sha256::digest(&params_bytes)) == account.recibo.params_sha256,
        &format!("{params_path} é o arquivo de parâmetros que o motor usou"),
    );

    let input = &account.entrada;
    let recomputed = feed_engine::rank(
        input.mode,
        &input.viewer,
        &input.candidates,
        &input.edges,
        &params,
        input.now,
    );
    ok &= check(
        output_sha256(&recomputed) == account.recibo.output_sha256,
        &format!(
            "refazendo a conta aqui, a ordem dos {} posts é a mesma que o motor assinou",
            recomputed.len()
        ),
    );
    ok &= check(
        output_sha256(&account.saida) == account.recibo.output_sha256,
        "a saída do arquivo é a que o motor assinou",
    );

    let key = match flags.get("--chave") {
        Some(key) => key.clone(),
        None => {
            let key = account
                .chave_recibos
                .clone()
                .ok_or("falta a chave dos recibos")?;
            println!(
                "  (usando a chave que veio no arquivo: {key}. Confira se ela aparece numa entrada \
                 \"motor\" do registro público, ou passe --chave)"
            );
            key
        }
    };
    ok &= check(
        account.recibo.verify(&decode_key(&key)?),
        "a assinatura do recibo é da chave do motor",
    );

    let published = match flags.get("--registro") {
        Some(path) => Some(load_registry(path, flags.get("--cabecalho"))?),
        None => None,
    };
    if let Some(published) = &published {
        ok &= published.ok;
        ok &= check(
            published
                .of_kind("motor")
                .any(|payload| payload["chave_recibos"].as_str() == Some(key.as_str())),
            "a chave do recibo é a de uma versão do motor publicada no registro",
        );
    }

    match &account.retrato {
        Some(snapshot) => ok &= data_proofs(&account, snapshot, published.as_ref())?,
        None => println!(
            "  (a conta não traz retrato do grafo: os dados de entrada não foram conferidos)"
        ),
    }
    Ok(ok)
}

/// Confere que cada ligação usada no feed estava no retrato do grafo.
fn data_proofs(
    account: &FeedAccount,
    snapshot: &SnapshotJson,
    published: Option<&Published>,
) -> Result<bool, String> {
    let root = parse_hash(&snapshot.raiz).ok_or("raiz do retrato mal formada")?;
    let proofs = account.provas.as_ref().ok_or("o retrato veio sem provas")?;
    let recent = account
        .recentes
        .as_ref()
        .ok_or("o retrato veio sem a lista de recentes")?;
    let input = &account.entrada;
    let alias = |number: u64| {
        account
            .pseudonimos
            .get(&number.to_string())
            .cloned()
            .ok_or(format!("falta o pseudônimo de {number}"))
    };
    let path = |hashes: &[String]| -> Result<Vec<Hash>, String> {
        hashes
            .iter()
            .map(|h| parse_hash(h).ok_or_else(|| "hash mal formado numa prova".to_string()))
            .collect()
    };

    let mut ok = true;
    println!(
        "Retrato do grafo {} ({} ligações)",
        snapshot.id, snapshot.tamanho
    );

    let distinct: std::collections::BTreeSet<&String> = account.pseudonimos.values().collect();
    ok &= check(
        distinct.len() == account.pseudonimos.len(),
        "cada número da entrada tem um pseudônimo só seu",
    );

    let mut every_edge = true;
    let mut covered = vec![false; input.edges.len()];
    for proof in &proofs.ligacoes {
        let edge = input
            .edges
            .get(proof.item)
            .ok_or("prova de uma ligação que não existe")?;
        let text = match edge.kind {
            EdgeKind::Like => format!("like|{}|{}|{}", alias(edge.user_id)?, edge.post_id, edge.at),
            EdgeKind::Watch => format!(
                "watch|{}|{}|{}|{}",
                alias(edge.user_id)?,
                edge.post_id,
                edge.watched_ms,
                edge.at
            ),
        };
        every_edge &= verify_inclusion(
            &leaf_hash(text.as_bytes()),
            proof.folha,
            snapshot.tamanho,
            &path(&proof.caminho)?,
            &root,
        );
        covered[proof.item] = true;
    }
    // Ligação sem prova só vale se for mais nova que o retrato: o que
    // aconteceu antes dele tinha que estar nele.
    let taken_at = parse_utc(&snapshot.em).ok_or("hora do retrato mal formada")?;
    let mut recent_are_newer = true;
    for item in &recent.ligacoes {
        if let Some(slot) = covered.get_mut(*item) {
            *slot = true;
        }
        recent_are_newer &= input
            .edges
            .get(*item)
            .is_some_and(|edge| edge.at >= taken_at);
    }
    ok &= check(
        every_edge,
        &format!(
            "as {} curtidas e views com prova estavam no retrato",
            proofs.ligacoes.len()
        ),
    );
    ok &= check(
        covered.iter().all(|c| *c),
        &format!(
            "nenhuma ligação ficou sem prova; {} vieram depois do retrato",
            recent.ligacoes.len()
        ),
    );
    ok &= check(
        recent_are_newer,
        &format!(
            "as ligações sem prova são mesmo mais novas que o retrato ({})",
            snapshot.em
        ),
    );

    let viewer = alias(input.viewer.id)?;
    let mut every_follow = true;
    let mut followed: std::collections::BTreeSet<u64> = recent
        .seguindo
        .iter()
        .map(|follow| follow.seguido)
        .collect();
    every_follow &= recent
        .seguindo
        .iter()
        .all(|follow| follow.desde >= taken_at);
    for proof in &proofs.seguindo {
        every_follow &= input.viewer.follows.contains(&proof.seguido);
        let text = format!("follow|{viewer}|{}|{}", alias(proof.seguido)?, proof.desde);
        every_follow &= verify_inclusion(
            &leaf_hash(text.as_bytes()),
            proof.folha,
            snapshot.tamanho,
            &path(&proof.caminho)?,
            &root,
        );
        followed.insert(proof.seguido);
    }
    ok &= check(
        every_follow && followed == input.viewer.follows,
        &format!(
            "quem você segue estava no retrato ou começou depois dele ({} com prova, {} mais novos)",
            proofs.seguindo.len(),
            recent.seguindo.len()
        ),
    );

    if let Some(published) = published {
        ok &= check(
            published.of_kind("raiz-dados").any(|payload| {
                payload["raiz"].as_str() == Some(snapshot.raiz.as_str())
                    && payload["retrato"].as_u64() == Some(snapshot.id)
                    && payload["ligacoes"].as_u64() == Some(snapshot.tamanho)
                    && payload["em"].as_str() == Some(snapshot.em.as_str())
            }),
            "a raiz, o tamanho e a hora do retrato estão publicados no registro público",
        );
    } else {
        println!("  (passe --registro entradas.json para conferir que a raiz foi publicada)");
    }
    Ok(ok)
}

// ---------------------------------------------------------------------------
// Pagamento

#[derive(Deserialize)]
struct Statement {
    mes: String,
    criador: String,
    parametros_sha256: String,
    entrada: ads_engine::closing::CreatorMonth,
    resultado: ads_engine::closing::CreatorResult,
    fechamento: Closing,
    provas: Vec<LeafProof>,
}

#[derive(Deserialize)]
struct Closing {
    raiz: String,
    folhas: u64,
}

#[derive(Deserialize)]
struct LeafProof {
    folha: u64,
    caminho: Vec<String>,
}

fn payment(args: &[String]) -> Result<bool, String> {
    let (flags, rest) = flags(args)?;
    let statement_path = rest.first().ok_or("falta o arquivo do extrato")?;
    let statement: Statement = read_json(statement_path)?;
    let params_path = flag(&flags, "--parametros")?;
    let params_source =
        fs::read_to_string(params_path).map_err(|e| format!("{params_path}: {e}"))?;
    let params = ads_engine::Params::from_toml_str(&params_source).map_err(|e| e.to_string())?;

    println!("Extrato de {} · {}\n", statement.criador, statement.mes);
    let mut ok = check(
        format!("{:x}", Sha256::digest(params_source.as_bytes())) == statement.parametros_sha256,
        "os parâmetros são os mesmos que o motor usou no fechamento",
    );
    ok &= check(
        statement.entrada.creator == statement.criador && statement.entrada.month == statement.mes,
        "a entrada é deste criador e deste mês",
    );

    // Refaz a conta com o código do motor e compara campo a campo.
    let recomputed = ads_engine::closing::close(&statement.entrada, &params);
    ok &= check(
        recomputed.statuses == statement.resultado.statuses,
        &format!(
            "as views que contaram e as descartadas ({} contaram, {} descartadas)",
            recomputed.national_views + recomputed.regional_views,
            recomputed.discarded_views
        ),
    );
    ok &= check(
        recomputed.video_cents == statement.resultado.video_cents
            && recomputed.effective_views == statement.resultado.effective_views,
        &format!(
            "as faixas: {} views efetivas, {} nos vídeos",
            recomputed.effective_views,
            money(recomputed.video_cents)
        ),
    );
    ok &= check(
        recomputed.shorts_cents_each == statement.resultado.shorts_cents_each,
        &format!(
            "a sua parte em cada anúncio dos shorts ({} anúncios, {})",
            recomputed.shorts_cents_each.len(),
            money(recomputed.shorts_cents)
        ),
    );
    ok &= check(
        recomputed == statement.resultado,
        &format!(
            "o total: {}{}",
            money(recomputed.total_cents),
            if recomputed.payable {
                ", por PIX"
            } else {
                ", fica para o mês seguinte"
            }
        ),
    );

    // Cada linha do extrato está na árvore do fechamento.
    let root = parse_hash(&statement.fechamento.raiz).ok_or("raiz mal formada")?;
    let every_leaf = recomputed.leaves.len() == statement.provas.len()
        && recomputed
            .leaves
            .iter()
            .zip(&statement.provas)
            .all(|(text, proof)| {
                hashes(&proof.caminho).is_ok_and(|caminho| {
                    verify_inclusion(
                        &leaf_hash(text.as_bytes()),
                        proof.folha,
                        statement.fechamento.folhas,
                        &caminho,
                        &root,
                    )
                })
            });
    ok &= check(
        every_leaf,
        &format!(
            "as {} linhas do extrato estão na árvore do fechamento",
            recomputed.leaves.len()
        ),
    );

    if let Some(registry_path) = flags.get("--registro") {
        let published = load_registry(registry_path, flags.get("--cabecalho"))?;
        ok &= published.ok;
        ok &= check(
            published.of_kind("fechamento").any(|payload| {
                payload["raiz"].as_str() == Some(statement.fechamento.raiz.as_str())
                    && payload["mes"].as_str() == Some(statement.mes.as_str())
            }),
            "a raiz do fechamento está publicada no registro público",
        );
    } else {
        println!("  (passe --registro entradas.json para conferir que a raiz foi publicada)");
    }
    Ok(ok)
}

fn hashes(list: &[String]) -> Result<Vec<Hash>, String> {
    list.iter()
        .map(|text| parse_hash(text).ok_or_else(|| format!("hash mal formado: {text}")))
        .collect()
}

fn money(cents: u64) -> String {
    format!("R$ {},{:02}", cents / 100, cents % 100)
}

// ---------------------------------------------------------------------------
// Registro público

#[derive(Deserialize)]
struct HeadFile {
    head: HeadJson,
}

#[derive(Deserialize)]
struct HeadJson {
    size: u64,
    root: String,
    timestamp: i64,
    signature: String,
    public_key: String,
}

#[derive(Deserialize)]
struct EntriesFile {
    entries: Vec<EntryJson>,
}

#[derive(Deserialize)]
struct EntryJson {
    index: u64,
    kind: String,
    data: String,
    leaf_hash: String,
}

#[derive(Deserialize)]
struct ConsistencyJson {
    from: u64,
    to: u64,
    proof: Vec<String>,
}

fn registry(args: &[String]) -> Result<bool, String> {
    let (flags, files) = flags(args)?;
    let [head_path, entries_path] = files.as_slice() else {
        return Err("passe o registro.json e o entradas.json".into());
    };
    let head_file: HeadFile = read_json(head_path)?;
    let entries: EntriesFile = read_json(entries_path)?;
    let head = tree_head(&head_file.head)?;

    let mut ok = true;
    let key = flags
        .get("--chave")
        .cloned()
        .unwrap_or_else(|| head_file.head.public_key.clone());
    if !flags.contains_key("--chave") {
        println!(
            "  (usando a chave que veio no arquivo; compare com a publicada pela rede ou passe --chave)"
        );
    }
    ok &= check(
        head.verify(
            &decode_key(&key)?,
            &decode_signature(&head_file.head.signature)?,
        ),
        &format!(
            "o cabeçalho com {} entradas foi assinado pela chave do registro",
            head.size
        ),
    );

    let mut leaves: Vec<Hash> = Vec::new();
    let mut every_leaf = true;
    let mut kinds: BTreeMap<&str, usize> = BTreeMap::new();
    for (expected, entry) in entries.entries.iter().enumerate() {
        let leaf = leaf_hash(entry.data.as_bytes());
        every_leaf &= entry.index == expected as u64
            && parse_hash(&entry.leaf_hash) == Some(leaf)
            && entry.data.starts_with(&format!("{}\n", entry.kind));
        leaves.push(leaf);
        *kinds.entry(entry.kind.as_str()).or_default() += 1;
    }
    ok &= check(
        every_leaf,
        "cada entrada publicada gera o hash de folha que diz ter",
    );
    ok &= check(
        leaves.len() as u64 == head.size && root(&leaves) == head.root,
        "a raiz recalculada a partir das entradas é a do cabeçalho",
    );
    for (kind, count) in &kinds {
        println!("  {count} entrada(s) \"{kind}\"");
    }

    if let (Some(old_path), Some(proof_path)) =
        (flags.get("--anterior"), flags.get("--consistencia"))
    {
        let old_file: HeadFile = read_json(old_path)?;
        let old = tree_head(&old_file.head)?;
        let proof: ConsistencyJson = read_json(proof_path)?;
        let hashes: Vec<Hash> = proof
            .proof
            .iter()
            .map(|h| parse_hash(h).ok_or("hash mal formado na prova"))
            .collect::<Result<_, _>>()?;
        ok &= check(
            old.verify(
                &decode_key(&key)?,
                &decode_signature(&old_file.head.signature)?,
            ),
            "o cabeçalho antigo também foi assinado pelo registro",
        );
        ok &= check(
            proof.from == old.size
                && proof.to == head.size
                && verify_consistency(old.size, head.size, &old.root, &head.root, &hashes),
            &format!(
                "as {} entradas do cabeçalho antigo continuam iguais no novo, com {} entradas",
                old.size, head.size
            ),
        );
    }
    Ok(ok)
}

/// As entradas do registro, conferidas e já lidas.
struct Published {
    entries: Vec<(String, Value)>,
    ok: bool,
}

impl Published {
    fn of_kind<'a>(&'a self, kind: &'a str) -> impl Iterator<Item = &'a Value> + 'a {
        self.entries
            .iter()
            .filter(move |(entry_kind, _)| entry_kind == kind)
            .map(|(_, payload)| payload)
    }
}

/// Lê entradas.json conferindo o hash de cada entrada e, com o cabeçalho,
/// que elas são exatamente as que o registro assinou. Sem o cabeçalho, um
/// arquivo montado à mão passaria; por isso o aviso.
fn load_registry(entries_path: &str, head_path: Option<&String>) -> Result<Published, String> {
    let file: EntriesFile = read_json(entries_path)?;
    let mut ok = true;
    let mut leaves = Vec::with_capacity(file.entries.len());
    let mut entries = Vec::with_capacity(file.entries.len());
    let mut every_leaf = true;

    for (expected, entry) in file.entries.iter().enumerate() {
        let leaf = leaf_hash(entry.data.as_bytes());
        let prefix = format!("{}\n", entry.kind);
        every_leaf &= entry.index == expected as u64
            && parse_hash(&entry.leaf_hash) == Some(leaf)
            && entry.data.starts_with(&prefix);
        leaves.push(leaf);
        let payload = entry
            .data
            .strip_prefix(&prefix)
            .and_then(|json| serde_json::from_str(json).ok())
            .unwrap_or(Value::Null);
        entries.push((entry.kind.clone(), payload));
    }
    ok &= check(
        every_leaf,
        "cada entrada do registro gera o hash de folha que diz ter",
    );

    match head_path {
        Some(path) => {
            let head_file: HeadFile = read_json(path)?;
            let head = tree_head(&head_file.head)?;
            ok &= check(
                head.verify(
                    &decode_key(&head_file.head.public_key)?,
                    &decode_signature(&head_file.head.signature)?,
                ) && leaves.len() as u64 == head.size
                    && root(&leaves) == head.root,
                "as entradas são as do cabeçalho assinado do registro",
            );
        }
        None => println!(
            "  (passe também --cabecalho registro.json para conferir que estas entradas são as \
             que o registro assinou)"
        ),
    }
    Ok(Published { entries, ok })
}

/// "2026-10-10T22:41:23Z" em segundos Unix. Só o formato que a rede publica.
fn parse_utc(text: &str) -> Option<i64> {
    let b = text.as_bytes();
    if b.len() != 20 || b[4] != b'-' || b[7] != b'-' || b[10] != b'T' || b[19] != b'Z' {
        return None;
    }
    let number = |range: std::ops::Range<usize>| text.get(range)?.parse::<i64>().ok();
    let (year, month, day) = (number(0..4)?, number(5..7)?, number(8..10)?);
    let (hour, minute, second) = (number(11..13)?, number(14..16)?, number(17..19)?);
    if !(1..=12).contains(&month)
        || !(1..=31).contains(&day)
        || hour > 23
        || minute > 59
        || second > 60
    {
        return None;
    }
    // Dias desde 1970-01-01 (algoritmo de Howard Hinnant).
    let y = if month <= 2 { year - 1 } else { year };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let mp = (month + 9) % 12;
    let doy = (153 * mp + 2) / 5 + day - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    let days = era * 146_097 + doe - 719_468;
    Some(days * 86_400 + hour * 3600 + minute * 60 + second)
}

fn tree_head(json: &HeadJson) -> Result<TreeHead, String> {
    Ok(TreeHead {
        size: json.size,
        root: parse_hash(&json.root).ok_or("raiz mal formada")?,
        timestamp: json.timestamp,
    })
}

// ---------------------------------------------------------------------------
// Utilidades

fn decode_key(text: &str) -> Result<[u8; 32], String> {
    B64.decode(text)
        .ok()
        .and_then(|bytes| bytes.try_into().ok())
        .ok_or_else(|| "chave mal formada (esperava 32 bytes em base64)".into())
}

fn decode_signature(text: &str) -> Result<[u8; 64], String> {
    B64.decode(text)
        .ok()
        .and_then(|bytes| bytes.try_into().ok())
        .ok_or_else(|| "assinatura mal formada".into())
}

fn read_json<T: for<'de> Deserialize<'de>>(path: &str) -> Result<T, String> {
    let text = fs::read_to_string(path).map_err(|e| format!("{path}: {e}"))?;
    let value: Value = serde_json::from_str(&text).map_err(|e| format!("{path}: {e}"))?;
    serde_json::from_value(value).map_err(|e| format!("{path}: {e}"))
}

type Flags = BTreeMap<String, String>;

fn flags(args: &[String]) -> Result<(Flags, Vec<String>), String> {
    let mut flags = BTreeMap::new();
    let mut rest = Vec::new();
    let mut iter = args.iter();
    while let Some(arg) = iter.next() {
        if arg.starts_with("--") {
            let value = iter.next().ok_or(format!("{arg} precisa de um valor"))?;
            flags.insert(arg.clone(), value.clone());
        } else {
            rest.push(arg.clone());
        }
    }
    Ok((flags, rest))
}

fn flag<'a>(flags: &'a Flags, name: &str) -> Result<&'a str, String> {
    flags
        .get(name)
        .map(String::as_str)
        .ok_or(format!("falta {name}"))
}

#[cfg(test)]
mod tests {
    use super::parse_utc;

    #[test]
    fn reads_the_time_the_network_publishes() {
        assert_eq!(parse_utc("1970-01-01T00:00:00Z"), Some(0));
        assert_eq!(parse_utc("2026-10-10T22:41:23Z"), Some(1_791_672_083));
        assert_eq!(parse_utc("2024-02-29T12:00:00Z"), Some(1_709_208_000));
        assert_eq!(parse_utc("2026-10-10 22:41:23"), None);
        assert_eq!(parse_utc("2026-13-10T22:41:23Z"), None);
    }
}
