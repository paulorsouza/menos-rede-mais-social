//! Cerimônia distribuída (DKG): a chave do grupo nasce sem existir inteira em
//! lugar nenhum, nem por um instante.
//!
//! É o DKG de Pedersen, com verificação de Feldman e prova de conhecimento do
//! termo independente de cada guardião (como no FROST, contra quem escolhe a
//! própria parte da chave depois de ver as dos outros).
//!
//! 1. Cada guardião gera uma chave de transporte e publica a parte pública.
//!    Ela só serve para receber as subfatias desta cerimônia.
//! 2. Rodada 1: cada guardião sorteia um polinômio de grau `threshold - 1`,
//!    publica os compromissos dos coeficientes (`a_k·G`), a prova de que
//!    conhece `a_0` e, para cada outro guardião, a subfatia `f(j)` cifrada com
//!    a chave de transporte dele. O arquivo é público.
//! 3. Rodada 2: cada guardião abre as subfatias que recebeu, confere cada uma
//!    contra os compromissos de quem mandou e soma: a soma é a fatia dele. Se
//!    alguma não confere, a cerimônia para e aponta quem mandou.
//!
//! Qualquer pessoa refaz `guardioes.toml` a partir dos arquivos da rodada 1:
//! a chave pública é a soma dos `a_0·G`, e a chave de conferência de cada
//! guardião sai dos compromissos. Todos os guardiões chegam ao mesmo arquivo.
//!
//! Limite conhecido: no DKG de Pedersen, quem age por último pode enviesar a
//! distribuição da chave pública. Para ElGamal com limiar isso não ajuda a
//! abrir nada (Gennaro, Jarecki, Krawczyk e Rabin, 2003).

use std::collections::{BTreeMap, BTreeSet};

use base64::{Engine as _, engine::general_purpose::STANDARD as B64};
use chacha20poly1305::{
    ChaCha20Poly1305, Key, Nonce,
    aead::{Aead, KeyInit, Payload},
};
use curve25519_dalek::{
    constants::RISTRETTO_BASEPOINT_POINT as G, ristretto::RistrettoPoint, scalar::Scalar,
};
use hkdf::Hkdf;
use rand_core::{OsRng, RngCore};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256, Sha512};
use zeroize::Zeroize;

use crate::{
    Error, Guardians, Member, Share, decode_point, decode_scalar, encode_point, encode_scalar,
};

const POK_DOMAIN: &[u8] = b"rede-social cofre dkg prova v1";
const TRANSPORT_INFO: &[u8] = b"rede-social cofre dkg transporte v1";

/// A chave de transporte de um guardião. A parte secreta fica com ele e é
/// apagada no fim da cerimônia.
pub struct TransportKey {
    pub index: u8,
    secret: Scalar,
}

impl Drop for TransportKey {
    fn drop(&mut self) {
        self.secret.zeroize();
    }
}

impl TransportKey {
    pub fn generate(index: u8) -> Result<Self, Error> {
        if index == 0 {
            return Err(Error::InvalidParams("o guardião 0 não existe".into()));
        }
        Ok(TransportKey {
            index,
            secret: Scalar::random(&mut OsRng),
        })
    }

    pub fn public(&self) -> TransportPublic {
        TransportPublic {
            index: self.index,
            key: encode_point(&(self.secret * G)),
        }
    }

    pub fn to_file(&self) -> TransportSecretFile {
        TransportSecretFile {
            index: self.index,
            secret: encode_scalar(&self.secret),
        }
    }

    pub fn from_file(file: &TransportSecretFile) -> Result<Self, Error> {
        Ok(TransportKey {
            index: file.index,
            secret: decode_scalar(&file.secret)?,
        })
    }
}

/// A parte pública da chave de transporte, como vai para os outros.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransportPublic {
    pub index: u8,
    pub key: String,
}

/// A parte secreta, em arquivo. Nunca sai do computador do guardião.
#[derive(Debug, Serialize, Deserialize)]
pub struct TransportSecretFile {
    pub index: u8,
    pub secret: String,
}

/// O arquivo público de um guardião na rodada 1.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Round1 {
    /// Identifica a cerimônia, para um arquivo de outra não ser reaproveitado.
    pub ceremony: String,
    pub index: u8,
    pub name: String,
    pub threshold: u8,
    /// `a_k·G`, do termo independente ao de maior grau.
    pub commitments: Vec<String>,
    /// Prova de que quem publicou conhece `a_0` (Schnorr).
    pub proof: ProofFile,
    /// A subfatia de cada outro guardião, cifrada para ele.
    pub shares: BTreeMap<u8, EncryptedShare>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProofFile {
    pub commitment: String,
    pub response: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EncryptedShare {
    pub ephemeral: String,
    pub nonce: String,
    pub ciphertext: String,
}

/// Rodada 1 de um guardião. `transports` tem a chave de transporte de todos,
/// inclusive a dele; o número de guardiões sai daí.
pub fn round1(
    ceremony: &str,
    index: u8,
    name: &str,
    threshold: u8,
    transports: &[TransportPublic],
) -> Result<Round1, Error> {
    let transports = transport_keys(transports)?;
    check_sizes(threshold, &transports)?;
    if !transports.contains_key(&index) {
        return Err(Error::InvalidParams(format!(
            "falta a chave de transporte do guardião {index}"
        )));
    }

    let mut coefficients: Vec<Scalar> =
        (0..threshold).map(|_| Scalar::random(&mut OsRng)).collect();
    let commitments: Vec<RistrettoPoint> = coefficients.iter().map(|a| a * G).collect();

    let mut nonce = Scalar::random(&mut OsRng);
    let proof_commitment = nonce * G;
    let challenge = pok_challenge(ceremony, index, &commitments[0], &proof_commitment);
    let proof = ProofFile {
        commitment: encode_point(&proof_commitment),
        response: encode_scalar(&(nonce + challenge * coefficients[0])),
    };
    nonce.zeroize();

    // A própria subfatia também vai cifrada, para a própria chave: assim a
    // rodada 2 trata todas do mesmo jeito e o polinômio pode ser apagado já.
    let mut shares = BTreeMap::new();
    for (&recipient, transport) in &transports {
        let mut value = evaluate(&coefficients, recipient);
        shares.insert(
            recipient,
            encrypt_share(ceremony, index, recipient, transport, &value),
        );
        value.zeroize();
    }
    coefficients.zeroize();

    Ok(Round1 {
        ceremony: ceremony.to_string(),
        index,
        name: name.to_string(),
        threshold,
        commitments: commitments.iter().map(encode_point).collect(),
        proof,
        shares,
    })
}

/// Rodada 2: abre as subfatias deste guardião, confere cada uma e devolve a
/// fatia dele e os parâmetros públicos.
pub fn round2(transport: &TransportKey, rounds: &[Round1]) -> Result<(Share, Guardians), Error> {
    let (ceremony, guardians, commitments) = public_parts(rounds)?;
    let me = transport.index;
    if !guardians.members.contains_key(&me) {
        return Err(Error::InvalidParams(format!(
            "o guardião {me} não está nesta cerimônia"
        )));
    }

    let mut secret = Scalar::ZERO;
    for round in rounds {
        let encrypted = round.shares.get(&me).ok_or(Error::Complaint {
            dealer: round.index,
            reason: "não mandou a subfatia",
        })?;
        let mut value =
            decrypt_share(&ceremony, round.index, me, transport, encrypted).map_err(|_| {
                Error::Complaint {
                    dealer: round.index,
                    reason: "a subfatia não abre",
                }
            })?;
        if value * G != evaluate_points(&commitments[&round.index], me) {
            value.zeroize();
            return Err(Error::Complaint {
                dealer: round.index,
                reason: "a subfatia não confere com os compromissos",
            });
        }
        secret += value;
        value.zeroize();
    }

    let share = Share { index: me, secret };
    if share.secret * G != guardians.members[&me].verification_key {
        return Err(Error::InvalidParams(
            "a fatia não bate com a chave de conferência".into(),
        ));
    }
    Ok((share, guardians))
}

/// Os parâmetros públicos (`guardioes.toml`) a partir dos arquivos da rodada
/// 1. Qualquer pessoa refaz, sem segredo nenhum.
pub fn public_params(rounds: &[Round1]) -> Result<Guardians, Error> {
    public_parts(rounds).map(|(_, guardians, _)| guardians)
}

type Commitments = BTreeMap<u8, Vec<RistrettoPoint>>;

fn public_parts(rounds: &[Round1]) -> Result<(String, Guardians, Commitments), Error> {
    let first = rounds
        .first()
        .ok_or(Error::InvalidParams("nenhum arquivo da rodada 1".into()))?;
    let ceremony = first.ceremony.clone();
    let threshold = first.threshold;
    let indices: BTreeSet<u8> = rounds.iter().map(|round| round.index).collect();
    if indices.len() != rounds.len() {
        return Err(Error::InvalidParams("guardião repetido na rodada 1".into()));
    }
    if indices.contains(&0) || threshold < 2 || usize::from(threshold) > indices.len() {
        return Err(Error::InvalidParams(
            "o mínimo de guardiões não bate com a lista".into(),
        ));
    }

    let mut commitments = BTreeMap::new();
    for round in rounds {
        if round.ceremony != ceremony || round.threshold != threshold {
            return Err(Error::Complaint {
                dealer: round.index,
                reason: "é de outra cerimônia ou de outro mínimo",
            });
        }
        let points = round
            .commitments
            .iter()
            .map(|text| decode_point(text))
            .collect::<Result<Vec<_>, _>>()?;
        if points.len() != usize::from(threshold) {
            return Err(Error::Complaint {
                dealer: round.index,
                reason: "o polinômio não tem o grau combinado",
            });
        }
        let shares: BTreeSet<u8> = round.shares.keys().copied().collect();
        if shares != indices {
            return Err(Error::Complaint {
                dealer: round.index,
                reason: "não mandou uma subfatia para cada guardião",
            });
        }

        let proof_commitment = decode_point(&round.proof.commitment)?;
        let response = decode_scalar(&round.proof.response)?;
        let challenge = pok_challenge(&ceremony, round.index, &points[0], &proof_commitment);
        if response * G != proof_commitment + challenge * points[0] {
            return Err(Error::Complaint {
                dealer: round.index,
                reason: "a prova do termo independente não confere",
            });
        }
        commitments.insert(round.index, points);
    }

    let public_key = commitments.values().map(|points| points[0]).sum();
    let members = rounds
        .iter()
        .map(|round| {
            let verification_key = commitments
                .values()
                .map(|points| evaluate_points(points, round.index))
                .sum();
            (
                round.index,
                Member {
                    name: round.name.clone(),
                    verification_key,
                },
            )
        })
        .collect();

    let guardians = Guardians {
        version: 1,
        threshold,
        public_key,
        members,
    };
    guardians.check_consistent()?;
    Ok((ceremony, guardians, commitments))
}

fn transport_keys(transports: &[TransportPublic]) -> Result<BTreeMap<u8, RistrettoPoint>, Error> {
    let mut keys = BTreeMap::new();
    for transport in transports {
        if transport.index == 0 {
            return Err(Error::InvalidParams("o guardião 0 não existe".into()));
        }
        if keys
            .insert(transport.index, decode_point(&transport.key)?)
            .is_some()
        {
            return Err(Error::InvalidParams(format!(
                "chave de transporte repetida para o guardião {}",
                transport.index
            )));
        }
    }
    Ok(keys)
}

fn check_sizes(threshold: u8, transports: &BTreeMap<u8, RistrettoPoint>) -> Result<(), Error> {
    if threshold < 2 || usize::from(threshold) > transports.len() {
        return Err(Error::InvalidParams(format!(
            "o mínimo precisa estar entre 2 e {}, veio {threshold}",
            transports.len()
        )));
    }
    Ok(())
}

fn evaluate(coefficients: &[Scalar], x: u8) -> Scalar {
    let x = Scalar::from(u64::from(x));
    coefficients
        .iter()
        .rev()
        .fold(Scalar::ZERO, |acc, coefficient| acc * x + coefficient)
}

fn evaluate_points(points: &[RistrettoPoint], x: u8) -> RistrettoPoint {
    let x = Scalar::from(u64::from(x));
    points
        .iter()
        .rev()
        .fold(RistrettoPoint::default(), |acc, point| acc * x + point)
}

fn pok_challenge(
    ceremony: &str,
    index: u8,
    constant: &RistrettoPoint,
    commitment: &RistrettoPoint,
) -> Scalar {
    let mut hash = Sha512::new();
    hash.update(POK_DOMAIN);
    hash.update((ceremony.len() as u64).to_be_bytes());
    hash.update(ceremony.as_bytes());
    hash.update([index]);
    for point in [G, *constant, *commitment] {
        hash.update(point.compress().as_bytes());
    }
    Scalar::from_hash(hash)
}

fn transport_cipher(
    shared: &RistrettoPoint,
    ephemeral: &RistrettoPoint,
    recipient: &RistrettoPoint,
) -> ChaCha20Poly1305 {
    let mut salt = Vec::with_capacity(64);
    salt.extend_from_slice(ephemeral.compress().as_bytes());
    salt.extend_from_slice(recipient.compress().as_bytes());
    let mut key = [0u8; 32];
    Hkdf::<Sha256>::new(Some(&salt), shared.compress().as_bytes())
        .expand(TRANSPORT_INFO, &mut key)
        .expect("32 bytes cabem no HKDF-SHA256");
    let cipher = ChaCha20Poly1305::new(Key::from_slice(&key));
    key.zeroize();
    cipher
}

fn share_aad(ceremony: &str, dealer: u8, recipient: u8) -> Vec<u8> {
    let mut aad = ceremony.as_bytes().to_vec();
    aad.extend_from_slice(&[0, dealer, recipient]);
    aad
}

fn encrypt_share(
    ceremony: &str,
    dealer: u8,
    recipient: u8,
    transport: &RistrettoPoint,
    value: &Scalar,
) -> EncryptedShare {
    let mut e = Scalar::random(&mut OsRng);
    let ephemeral = e * G;
    let shared = e * transport;
    e.zeroize();

    let mut nonce = [0u8; 12];
    OsRng.fill_bytes(&mut nonce);
    let ciphertext = transport_cipher(&shared, &ephemeral, transport)
        .encrypt(
            Nonce::from_slice(&nonce),
            Payload {
                msg: value.as_bytes(),
                aad: &share_aad(ceremony, dealer, recipient),
            },
        )
        .expect("cifrar com chave e nonce do tamanho certo não falha");

    EncryptedShare {
        ephemeral: encode_point(&ephemeral),
        nonce: B64.encode(nonce),
        ciphertext: B64.encode(ciphertext),
    }
}

fn decrypt_share(
    ceremony: &str,
    dealer: u8,
    recipient: u8,
    transport: &TransportKey,
    encrypted: &EncryptedShare,
) -> Result<Scalar, Error> {
    let ephemeral = decode_point(&encrypted.ephemeral)?;
    let nonce: [u8; 12] = B64
        .decode(&encrypted.nonce)
        .ok()
        .and_then(|bytes| bytes.try_into().ok())
        .ok_or(Error::InvalidEncoding("nonce"))?;
    let ciphertext = B64
        .decode(&encrypted.ciphertext)
        .map_err(|_| Error::InvalidEncoding("subfatia"))?;

    let own_public = transport.secret * G;
    let mut plaintext = transport_cipher(&(transport.secret * ephemeral), &ephemeral, &own_public)
        .decrypt(
            Nonce::from_slice(&nonce),
            Payload {
                msg: &ciphertext,
                aad: &share_aad(ceremony, dealer, recipient),
            },
        )
        .map_err(|_| Error::DecryptFailed)?;
    let bytes: Result<[u8; 32], _> = plaintext.as_slice().try_into();
    plaintext.zeroize();
    let bytes = bytes.map_err(|_| Error::InvalidEncoding("subfatia"))?;
    Option::from(Scalar::from_canonical_bytes(bytes)).ok_or(Error::InvalidEncoding("subfatia"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{open, partial, seal};

    fn run(threshold: u8, count: u8) -> (Vec<Round1>, Vec<TransportKey>) {
        let keys: Vec<TransportKey> = (1..=count)
            .map(|index| TransportKey::generate(index).unwrap())
            .collect();
        let publics: Vec<TransportPublic> = keys.iter().map(TransportKey::public).collect();
        let rounds = keys
            .iter()
            .map(|key| {
                round1(
                    "teste-1",
                    key.index,
                    &format!("Guardião {}", key.index),
                    threshold,
                    &publics,
                )
                .unwrap()
            })
            .collect();
        (rounds, keys)
    }

    #[test]
    fn every_guardian_reaches_the_same_params_and_any_three_open() {
        let (rounds, keys) = run(3, 5);
        let results: Vec<(Share, Guardians)> = keys
            .iter()
            .map(|key| round2(key, &rounds).unwrap())
            .collect();
        let public = public_params(&rounds).unwrap();
        for (_, guardians) in &results {
            assert_eq!(guardians, &public);
        }

        // O arquivo público passa pela mesma conferência do motor.
        let reloaded = Guardians::from_toml_str(&public.to_toml_string()).unwrap();
        assert_eq!(reloaded, public);

        let sealed = seal(&public.public_key, b"52998224725", b"cpf:conta-1");
        for trio in [[1u8, 2, 3], [1, 4, 5], [2, 3, 5]] {
            let partials: Vec<_> = trio
                .iter()
                .map(|i| partial(&results[usize::from(*i - 1)].0, &sealed, b"cpf:conta-1").unwrap())
                .collect();
            assert_eq!(
                open(&public, &sealed, &partials, b"cpf:conta-1").unwrap(),
                b"52998224725"
            );
        }
    }

    #[test]
    fn a_wrong_subshare_points_at_who_sent_it() {
        let (mut rounds, keys) = run(3, 5);
        // O guardião 2 manda para o 4 a subfatia que era do 5.
        let wrong = rounds[1].shares[&5].clone();
        rounds[1].shares.insert(4, wrong);

        assert!(matches!(
            round2(&keys[3], &rounds),
            Err(Error::Complaint { dealer: 2, .. })
        ));
        // Os outros não percebem, mas o 4 para a cerimônia.
        assert!(round2(&keys[0], &rounds).is_ok());
    }

    #[test]
    fn a_dealer_without_the_proof_is_refused() {
        let (mut rounds, _keys) = run(3, 5);
        rounds[2].proof = rounds[1].proof.clone();
        assert!(matches!(
            public_params(&rounds),
            Err(Error::Complaint { dealer: 3, .. })
        ));
    }

    #[test]
    fn files_from_another_ceremony_do_not_mix() {
        let (mut rounds, keys) = run(3, 5);
        rounds[0].ceremony = "outra".into();
        assert!(round2(&keys[1], &rounds).is_err());
    }
}
