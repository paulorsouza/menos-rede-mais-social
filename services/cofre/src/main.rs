//! Linha de comando dos guardiões do cofre do CPF.
//!
//! cofre cerimonia --minimo 3 --saida <pasta> <nome 1> ... <nome N>
//!     Gera uma fatia por guardião em <pasta>/fatia-N.json e escreve os
//!     parâmetros públicos em <pasta>/guardioes.toml. Rode num computador
//!     desligado da rede e entregue cada fatia ao seu guardião.
//!
//! cofre parcial --fatia <fatia.json> --pedido <pedido.json>
//!     Confere que cada selado do pedido foi feito para o contexto que está
//!     nele (a conta da ordem judicial) e calcula a parte deste guardião, com
//!     a prova de que a conta está certa. Antes, confira na ordem judicial que
//!     as contas listadas são as da ordem.
//!
//! cofre abrir --guardioes <guardioes.toml> --pedido <pedido.json> <parte.json>...
//!     Confere as partes e abre os itens do pedido.
//!
//! O pedido é o arquivo que a rede gera para cada ordem judicial:
//! {"order_id": 7, "items": [{"key": "cpf", "context": "...", "sealed": "..."}]}

use std::{collections::BTreeMap, env, fs, path::PathBuf, process};

use cofre::{Guardians, Partial, PartialWire, Sealed, Share, ShareFile};
use serde::{Deserialize, Serialize};

#[derive(Deserialize)]
struct Order {
    order_id: u64,
    items: Vec<Item>,
}

#[derive(Deserialize)]
struct Item {
    key: String,
    context: String,
    sealed: String,
}

#[derive(Serialize, Deserialize)]
struct GuardianPartials {
    order_id: u64,
    index: u8,
    partials: BTreeMap<String, PartialWire>,
}

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    let result = match args.first().map(String::as_str) {
        Some("cerimonia") => ceremony(&args[1..]),
        Some("parcial") => partial(&args[1..]),
        Some("abrir") => open(&args[1..]),
        _ => Err("uso: cofre cerimonia | parcial | abrir (veja o começo de src/main.rs)".into()),
    };
    if let Err(message) = result {
        eprintln!("{message}");
        process::exit(1);
    }
}

fn ceremony(args: &[String]) -> Result<(), String> {
    let (flags, names) = flags(args)?;
    let threshold: u8 = flag(&flags, "--minimo")?
        .parse()
        .map_err(|_| "--minimo precisa ser um número")?;
    let out = PathBuf::from(flag(&flags, "--saida")?);
    let count = u8::try_from(names.len()).map_err(|_| "guardiões demais")?;

    let ceremony = cofre::ceremony(threshold, count, &names).map_err(|e| e.to_string())?;
    fs::create_dir_all(&out).map_err(|e| e.to_string())?;
    for share in &ceremony.shares {
        let path = out.join(format!("fatia-{}.json", share.index));
        let json = serde_json::to_string_pretty(&share.to_file()).map_err(|e| e.to_string())?;
        fs::write(&path, json).map_err(|e| e.to_string())?;
    }
    fs::write(
        out.join("guardioes.toml"),
        ceremony.guardians.to_toml_string(),
    )
    .map_err(|e| e.to_string())?;
    eprintln!(
        "{count} fatias em {}. Entregue cada uma ao seu guardião e apague as cópias.",
        out.display()
    );
    Ok(())
}

fn partial(args: &[String]) -> Result<(), String> {
    let (flags, _) = flags(args)?;
    let file: ShareFile = read_json(flag(&flags, "--fatia")?)?;
    let share = Share::from_file(&file).map_err(|e| e.to_string())?;
    let order: Order = read_json(flag(&flags, "--pedido")?)?;

    let mut partials = BTreeMap::new();
    for item in &order.items {
        let sealed = Sealed::from_base64(&item.sealed).map_err(|e| e.to_string())?;
        let partial = cofre::partial(&share, &sealed, item.context.as_bytes())
            .map_err(|e| format!("{}: {e}", item.key))?;
        eprintln!("{}\t{}", item.key, item.context);
        partials.insert(item.key.clone(), PartialWire::from(&partial));
    }
    let out = GuardianPartials {
        order_id: order.order_id,
        index: share.index,
        partials,
    };
    println!(
        "{}",
        serde_json::to_string_pretty(&out).map_err(|e| e.to_string())?
    );
    Ok(())
}

fn open(args: &[String]) -> Result<(), String> {
    let (flags, files) = flags(args)?;
    let source = fs::read_to_string(flag(&flags, "--guardioes")?).map_err(|e| e.to_string())?;
    let guardians = Guardians::from_toml_str(&source).map_err(|e| e.to_string())?;
    let order: Order = read_json(flag(&flags, "--pedido")?)?;

    let mut answers: Vec<GuardianPartials> = Vec::new();
    for file in &files {
        let answer: GuardianPartials = read_json(file)?;
        if answer.order_id != order.order_id {
            return Err(format!("{file} é de outro pedido"));
        }
        answers.push(answer);
    }

    for item in &order.items {
        let sealed = Sealed::from_base64(&item.sealed).map_err(|e| e.to_string())?;
        let partials: Vec<Partial> = answers
            .iter()
            .filter_map(|answer| answer.partials.get(&item.key))
            .map(Partial::try_from)
            .collect::<Result<_, _>>()
            .map_err(|e| e.to_string())?;
        let text = cofre::open(&guardians, &sealed, &partials, item.context.as_bytes())
            .map_err(|e| format!("{}: {e}", item.key))?;
        println!("{}\t{}", item.key, String::from_utf8_lossy(&text));
    }
    Ok(())
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

fn read_json<T: for<'de> Deserialize<'de>>(path: &str) -> Result<T, String> {
    let text = fs::read_to_string(path).map_err(|e| format!("{path}: {e}"))?;
    serde_json::from_str(&text).map_err(|e| format!("{path}: {e}"))
}
