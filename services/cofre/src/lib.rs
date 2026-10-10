//! Cofre do CPF da -rede+social.
//!
//! A lei obriga a rede a identificar uma conta quando um juiz manda, mas
//! ninguém dentro da rede deveria conseguir fazer isso sozinho (seção 3 do
//! plano). Por isso o CPF fica cifrado com a chave pública de um grupo de
//! guardiões independentes, e abrir um CPF exige a participação de pelo menos
//! `threshold` deles (3 de 5).
//!
//! O esquema é ElGamal com limiar sobre o grupo Ristretto255:
//!
//! - Na cerimônia, a chave secreta do grupo é dividida em fatias pelo
//!   esquema de Shamir. Cada guardião guarda a sua fatia e publica a chave de
//!   conferência dela.
//! - Selar um CPF usa só a chave pública: sorteia `r`, publica `R = r·G` e
//!   cifra o texto com uma chave derivada de `r·P`. O selado leva também
//!   `R̄ = r·H` e uma prova de que quem selou conhece `r`, amarrada ao
//!   contexto (a conta) e ao texto cifrado. É o TDH2 de Shoup e Gennaro.
//! - Para abrir, cada guardião confere a prova do selado com o contexto que
//!   está no pedido, calcula a sua parte `D = fatia·R` e prova, sem revelar a
//!   fatia, que fez a conta certa. Três partes, combinadas pelos coeficientes
//!   de Lagrange, dão `r·P` e abrem aquele CPF. A parte de um guardião só
//!   serve para aquele `R`, então abrir uma conta não ajuda a abrir outra, e a
//!   chave secreta nunca é remontada na abertura.
//!
//! Sem a prova do selado, a rede poderia pedir a parte dos guardiões para
//! `k·R` de outra conta, com um contexto qualquer, e depois dividir por `k`:
//! o guardião abriria uma conta achando que abria outra. Com a prova, montar
//! um selado para `k·R` exige conhecer `k·r`, e quem não selou não conhece.
//!
//! Limite assumido na Fase 1: a cerimônia gera a chave inteira num computador
//! desligado da rede e a apaga em seguida. Antes do piloto, a cerimônia passa
//! a ser distribuída (DKG), e a chave inteira não existe nem por um instante.

use std::collections::{BTreeMap, BTreeSet};

use base64::{Engine as _, engine::general_purpose::STANDARD as B64};
use chacha20poly1305::{
    ChaCha20Poly1305, Key, Nonce,
    aead::{Aead, KeyInit, Payload},
};
use curve25519_dalek::{
    constants::RISTRETTO_BASEPOINT_POINT as G,
    ristretto::{CompressedRistretto, RistrettoPoint},
    scalar::Scalar,
};
use hkdf::Hkdf;
use rand_core::{OsRng, RngCore};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256, Sha512};
use zeroize::Zeroize;

const SEALED_VERSION: u8 = 2;
const KDF_INFO: &[u8] = b"rede-social cofre v1";
const PROOF_DOMAIN: &[u8] = b"rede-social cofre prova v1";
const SEAL_PROOF_DOMAIN: &[u8] = b"rede-social cofre selado v2";
const H_DOMAIN: &[u8] = b"rede-social cofre H v2";

/// O segundo gerador, `H`, que ninguém conhece como múltiplo de `G`.
fn h() -> RistrettoPoint {
    let mut bytes = [0u8; 64];
    bytes.copy_from_slice(&Sha512::digest(H_DOMAIN));
    RistrettoPoint::from_uniform_bytes(&bytes)
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Error {
    InvalidParams(String),
    InvalidEncoding(&'static str),
    UnknownGuardian(u8),
    BadProof(u8),
    /// O selado não prova que foi feito para este contexto.
    BadSealed,
    NotEnoughPartials {
        needed: u8,
        got: usize,
    },
    DecryptFailed,
}

impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Error::InvalidParams(message) => write!(f, "parâmetros inválidos: {message}"),
            Error::InvalidEncoding(what) => write!(f, "{what} mal formado"),
            Error::UnknownGuardian(index) => write!(f, "guardião {index} não existe"),
            Error::BadProof(index) => write!(f, "a parte do guardião {index} não confere"),
            Error::BadSealed => write!(f, "o selado não confere com o contexto do pedido"),
            Error::NotEnoughPartials { needed, got } => {
                write!(f, "precisa de {needed} guardiões, chegaram {got}")
            }
            Error::DecryptFailed => write!(f, "não foi possível abrir: dados ou contexto errados"),
        }
    }
}

impl std::error::Error for Error {}

/// A chave pública do grupo e a chave de conferência de cada guardião. É
/// público, fica em `params/guardioes.toml`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Guardians {
    pub version: u32,
    pub threshold: u8,
    pub public_key: RistrettoPoint,
    pub members: BTreeMap<u8, Member>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Member {
    pub name: String,
    pub verification_key: RistrettoPoint,
}

/// A fatia secreta de um guardião. Fica no cofre de hardware da instituição e
/// é apagada da memória quando sai de uso.
pub struct Share {
    pub index: u8,
    secret: Scalar,
}

impl Drop for Share {
    fn drop(&mut self) {
        self.secret.zeroize();
    }
}

/// O que sai da cerimônia: os parâmetros públicos e uma fatia por guardião.
pub struct Ceremony {
    pub guardians: Guardians,
    pub shares: Vec<Share>,
}

/// Um texto selado: o ponto efêmero `R`, `R̄ = r·H`, a prova de que quem
/// selou conhece `r`, o nonce e o texto cifrado.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Sealed {
    ephemeral: RistrettoPoint,
    ephemeral_h: RistrettoPoint,
    challenge: Scalar,
    response: Scalar,
    nonce: [u8; 12],
    ciphertext: Vec<u8>,
}

/// A parte de um guardião para abrir um selado, com a prova de que ele usou a
/// fatia certa.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Partial {
    pub index: u8,
    point: RistrettoPoint,
    challenge: Scalar,
    response: Scalar,
}

/// Gera as fatias de `count` guardiões, das quais `threshold` abrem um CPF.
pub fn ceremony(threshold: u8, count: u8, names: &[String]) -> Result<Ceremony, Error> {
    if threshold < 2 || threshold > count {
        return Err(Error::InvalidParams(format!(
            "o mínimo precisa estar entre 2 e {count}, veio {threshold}"
        )));
    }
    if names.len() != usize::from(count) {
        return Err(Error::InvalidParams("um nome por guardião".into()));
    }

    // Polinômio de grau threshold - 1; o termo independente é a chave.
    let mut coefficients: Vec<Scalar> =
        (0..threshold).map(|_| Scalar::random(&mut OsRng)).collect();
    let public_key = coefficients[0] * G;

    let mut shares = Vec::with_capacity(usize::from(count));
    let mut members = BTreeMap::new();
    for index in 1..=count {
        let x = Scalar::from(u64::from(index));
        let secret = coefficients
            .iter()
            .rev()
            .fold(Scalar::ZERO, |acc, coefficient| acc * x + coefficient);
        members.insert(
            index,
            Member {
                name: names[usize::from(index - 1)].clone(),
                verification_key: secret * G,
            },
        );
        shares.push(Share { index, secret });
    }
    coefficients.zeroize();

    Ok(Ceremony {
        guardians: Guardians {
            version: 1,
            threshold,
            public_key,
            members,
        },
        shares,
    })
}

/// Sela um texto com a chave do grupo. O contexto (por exemplo, "cpf:" e o id
/// da conta) entra como dado autenticado: um selado copiado para outra conta
/// não abre.
pub fn seal(public_key: &RistrettoPoint, plaintext: &[u8], context: &[u8]) -> Sealed {
    let mut r = Scalar::random(&mut OsRng);
    let ephemeral = r * G;
    let ephemeral_h = r * h();
    let shared = r * public_key;

    let mut nonce = [0u8; 12];
    OsRng.fill_bytes(&mut nonce);
    let cipher = cipher(&shared, &ephemeral);
    let ciphertext = cipher
        .encrypt(
            Nonce::from_slice(&nonce),
            Payload {
                msg: plaintext,
                aad: context,
            },
        )
        .expect("cifrar com chave e nonce do tamanho certo não falha");

    // Prova de que quem selou conhece r, amarrada ao contexto e ao texto.
    let mut s = Scalar::random(&mut OsRng);
    let challenge = seal_challenge(
        context,
        &nonce,
        &ciphertext,
        &ephemeral,
        &ephemeral_h,
        &(s * G),
        &(s * h()),
    );
    let response = s + challenge * r;
    s.zeroize();
    r.zeroize();

    Sealed {
        ephemeral,
        ephemeral_h,
        challenge,
        response,
        nonce,
        ciphertext,
    }
}

/// Confere que o selado foi feito para este contexto, por quem conhecia `r`.
/// O guardião faz isso antes de calcular a parte dele.
pub fn verify_sealed(sealed: &Sealed, context: &[u8]) -> Result<(), Error> {
    let commitment_g = sealed.response * G - sealed.challenge * sealed.ephemeral;
    let commitment_h = sealed.response * h() - sealed.challenge * sealed.ephemeral_h;
    let expected = seal_challenge(
        context,
        &sealed.nonce,
        &sealed.ciphertext,
        &sealed.ephemeral,
        &sealed.ephemeral_h,
        &commitment_g,
        &commitment_h,
    );
    if expected == sealed.challenge {
        Ok(())
    } else {
        Err(Error::BadSealed)
    }
}

/// O guardião confere o selado com o contexto do pedido, calcula a sua parte
/// e prova que usou a fatia cuja chave de conferência está publicada.
pub fn partial(share: &Share, sealed: &Sealed, context: &[u8]) -> Result<Partial, Error> {
    verify_sealed(sealed, context)?;
    let point = share.secret * sealed.ephemeral;
    let verification_key = share.secret * G;

    // Prova de igualdade de logaritmos (Chaum-Pedersen): o mesmo segredo liga
    // G à chave de conferência e R à parte.
    let mut nonce = Scalar::random(&mut OsRng);
    let commitment_g = nonce * G;
    let commitment_r = nonce * sealed.ephemeral;
    let challenge = challenge(
        &verification_key,
        &sealed.ephemeral,
        &point,
        &commitment_g,
        &commitment_r,
    );
    let response = nonce + challenge * share.secret;
    nonce.zeroize();

    Ok(Partial {
        index: share.index,
        point,
        challenge,
        response,
    })
}

/// Confere a prova de uma parte contra a chave de conferência publicada.
pub fn verify_partial(
    guardians: &Guardians,
    sealed: &Sealed,
    partial: &Partial,
) -> Result<(), Error> {
    let member = guardians
        .members
        .get(&partial.index)
        .ok_or(Error::UnknownGuardian(partial.index))?;
    let commitment_g = partial.response * G - partial.challenge * member.verification_key;
    let commitment_r = partial.response * sealed.ephemeral - partial.challenge * partial.point;
    let expected = challenge(
        &member.verification_key,
        &sealed.ephemeral,
        &partial.point,
        &commitment_g,
        &commitment_r,
    );
    if expected == partial.challenge {
        Ok(())
    } else {
        Err(Error::BadProof(partial.index))
    }
}

/// Abre um selado com as partes de pelo menos `threshold` guardiões. Cada
/// parte é conferida antes, e a que não confere fica de fora: um guardião com
/// defeito não impede os outros de abrir. Partes repetidas do mesmo guardião
/// contam uma vez.
pub fn open(
    guardians: &Guardians,
    sealed: &Sealed,
    partials: &[Partial],
    context: &[u8],
) -> Result<Vec<u8>, Error> {
    verify_sealed(sealed, context)?;
    let mut chosen: BTreeMap<u8, &Partial> = BTreeMap::new();
    for partial in partials {
        if verify_partial(guardians, sealed, partial).is_ok() {
            chosen.entry(partial.index).or_insert(partial);
        }
    }
    if chosen.len() < usize::from(guardians.threshold) {
        return Err(Error::NotEnoughPartials {
            needed: guardians.threshold,
            got: chosen.len(),
        });
    }

    let used: Vec<&Partial> = chosen
        .into_values()
        .take(usize::from(guardians.threshold))
        .collect();
    let indices: BTreeSet<u8> = used.iter().map(|partial| partial.index).collect();
    let shared: RistrettoPoint = used
        .iter()
        .map(|partial| lagrange_at_zero(partial.index, &indices) * partial.point)
        .sum();

    cipher(&shared, &sealed.ephemeral)
        .decrypt(
            Nonce::from_slice(&sealed.nonce),
            Payload {
                msg: &sealed.ciphertext,
                aad: context,
            },
        )
        .map_err(|_| Error::DecryptFailed)
}

fn lagrange_at_zero(index: u8, indices: &BTreeSet<u8>) -> Scalar {
    lagrange_at(0, index, indices)
}

/// O coeficiente de Lagrange de `index`, no ponto `x`, para estes índices.
fn lagrange_at(x: u8, index: u8, indices: &BTreeSet<u8>) -> Scalar {
    let x = Scalar::from(u64::from(x));
    let x_i = Scalar::from(u64::from(index));
    indices
        .iter()
        .filter(|other| **other != index)
        .fold(Scalar::ONE, |acc, other| {
            let x_j = Scalar::from(u64::from(*other));
            acc * (x - x_j) * (x_i - x_j).invert()
        })
}

fn seal_challenge(
    context: &[u8],
    nonce: &[u8; 12],
    ciphertext: &[u8],
    ephemeral: &RistrettoPoint,
    ephemeral_h: &RistrettoPoint,
    commitment_g: &RistrettoPoint,
    commitment_h: &RistrettoPoint,
) -> Scalar {
    let mut hash = Sha512::new();
    hash.update(SEAL_PROOF_DOMAIN);
    // Os campos de tamanho livre levam o tamanho antes, para não se confundirem.
    hash.update((context.len() as u64).to_be_bytes());
    hash.update(context);
    hash.update(nonce);
    hash.update((ciphertext.len() as u64).to_be_bytes());
    hash.update(ciphertext);
    for element in [
        G,
        h(),
        *ephemeral,
        *ephemeral_h,
        *commitment_g,
        *commitment_h,
    ] {
        hash.update(element.compress().as_bytes());
    }
    Scalar::from_hash(hash)
}

fn cipher(shared: &RistrettoPoint, ephemeral: &RistrettoPoint) -> ChaCha20Poly1305 {
    let mut key = [0u8; 32];
    Hkdf::<Sha256>::new(
        Some(ephemeral.compress().as_bytes()),
        shared.compress().as_bytes(),
    )
    .expand(KDF_INFO, &mut key)
    .expect("32 bytes cabem no HKDF-SHA256");
    let cipher = ChaCha20Poly1305::new(Key::from_slice(&key));
    key.zeroize();
    cipher
}

fn challenge(
    verification_key: &RistrettoPoint,
    ephemeral: &RistrettoPoint,
    point: &RistrettoPoint,
    commitment_g: &RistrettoPoint,
    commitment_r: &RistrettoPoint,
) -> Scalar {
    let mut hash = Sha512::new();
    hash.update(PROOF_DOMAIN);
    for element in [
        G,
        *verification_key,
        *ephemeral,
        *point,
        *commitment_g,
        *commitment_r,
    ] {
        hash.update(element.compress().as_bytes());
    }
    Scalar::from_hash(hash)
}

// ---------------------------------------------------------------------------
// Formatos de arquivo e de rede. Pontos e escalares viajam em base64.

fn encode_point(point: &RistrettoPoint) -> String {
    B64.encode(point.compress().as_bytes())
}

fn decode_point(text: &str) -> Result<RistrettoPoint, Error> {
    let bytes = B64
        .decode(text)
        .map_err(|_| Error::InvalidEncoding("ponto"))?;
    CompressedRistretto::from_slice(&bytes)
        .map_err(|_| Error::InvalidEncoding("ponto"))?
        .decompress()
        .ok_or(Error::InvalidEncoding("ponto"))
}

fn encode_scalar(scalar: &Scalar) -> String {
    B64.encode(scalar.as_bytes())
}

fn decode_scalar(text: &str) -> Result<Scalar, Error> {
    let bytes: [u8; 32] = B64
        .decode(text)
        .map_err(|_| Error::InvalidEncoding("escalar"))?
        .try_into()
        .map_err(|_| Error::InvalidEncoding("escalar"))?;
    Option::from(Scalar::from_canonical_bytes(bytes)).ok_or(Error::InvalidEncoding("escalar"))
}

const SEALED_HEADER: usize = 1 + 4 * 32 + 12;

impl Sealed {
    /// Versão, R, R̄, desafio, resposta, nonce e texto cifrado, em sequência.
    /// A versão 1, sem a prova, não é mais aceita.
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut bytes = Vec::with_capacity(SEALED_HEADER + self.ciphertext.len());
        bytes.push(SEALED_VERSION);
        bytes.extend_from_slice(self.ephemeral.compress().as_bytes());
        bytes.extend_from_slice(self.ephemeral_h.compress().as_bytes());
        bytes.extend_from_slice(self.challenge.as_bytes());
        bytes.extend_from_slice(self.response.as_bytes());
        bytes.extend_from_slice(&self.nonce);
        bytes.extend_from_slice(&self.ciphertext);
        bytes
    }

    pub fn from_bytes(bytes: &[u8]) -> Result<Self, Error> {
        if bytes.len() < SEALED_HEADER + 16 || bytes[0] != SEALED_VERSION {
            return Err(Error::InvalidEncoding("selado"));
        }
        let point = |range: std::ops::Range<usize>| {
            CompressedRistretto::from_slice(&bytes[range])
                .ok()
                .and_then(|point| point.decompress())
                .ok_or(Error::InvalidEncoding("selado"))
        };
        let scalar = |range: std::ops::Range<usize>| {
            let array: [u8; 32] = bytes[range].try_into().expect("32 bytes");
            Option::from(Scalar::from_canonical_bytes(array))
                .ok_or(Error::InvalidEncoding("selado"))
        };
        Ok(Sealed {
            ephemeral: point(1..33)?,
            ephemeral_h: point(33..65)?,
            challenge: scalar(65..97)?,
            response: scalar(97..129)?,
            nonce: bytes[129..141].try_into().expect("12 bytes"),
            ciphertext: bytes[SEALED_HEADER..].to_vec(),
        })
    }

    pub fn to_base64(&self) -> String {
        B64.encode(self.to_bytes())
    }

    pub fn from_base64(text: &str) -> Result<Self, Error> {
        let bytes = B64
            .decode(text)
            .map_err(|_| Error::InvalidEncoding("selado"))?;
        Self::from_bytes(&bytes)
    }
}

/// Uma parte como ela viaja entre o guardião e a rede.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PartialWire {
    pub index: u8,
    pub point: String,
    pub challenge: String,
    pub response: String,
}

impl From<&Partial> for PartialWire {
    fn from(partial: &Partial) -> Self {
        PartialWire {
            index: partial.index,
            point: encode_point(&partial.point),
            challenge: encode_scalar(&partial.challenge),
            response: encode_scalar(&partial.response),
        }
    }
}

impl TryFrom<&PartialWire> for Partial {
    type Error = Error;

    fn try_from(wire: &PartialWire) -> Result<Self, Error> {
        Ok(Partial {
            index: wire.index,
            point: decode_point(&wire.point)?,
            challenge: decode_scalar(&wire.challenge)?,
            response: decode_scalar(&wire.response)?,
        })
    }
}

/// A fatia de um guardião em arquivo. É segredo: nunca vai para o repositório
/// fora da demonstração.
#[derive(Debug, Serialize, Deserialize)]
pub struct ShareFile {
    pub index: u8,
    pub share: String,
}

impl Share {
    pub fn to_file(&self) -> ShareFile {
        ShareFile {
            index: self.index,
            share: encode_scalar(&self.secret),
        }
    }

    pub fn from_file(file: &ShareFile) -> Result<Self, Error> {
        Ok(Share {
            index: file.index,
            secret: decode_scalar(&file.share)?,
        })
    }
}

/// `params/guardioes.toml`.
#[derive(Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct GuardiansFile {
    version: u32,
    threshold: u8,
    public_key: String,
    guardians: Vec<MemberFile>,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct MemberFile {
    index: u8,
    name: String,
    verification_key: String,
}

impl Guardians {
    pub fn from_toml_str(source: &str) -> Result<Self, Error> {
        let file: GuardiansFile =
            toml::from_str(source).map_err(|error| Error::InvalidParams(error.to_string()))?;
        let mut members = BTreeMap::new();
        for member in &file.guardians {
            let previous = members.insert(
                member.index,
                Member {
                    name: member.name.clone(),
                    verification_key: decode_point(&member.verification_key)?,
                },
            );
            if previous.is_some() {
                return Err(Error::InvalidParams(format!(
                    "guardião {} repetido",
                    member.index
                )));
            }
        }
        if file.threshold < 2 || usize::from(file.threshold) > members.len() {
            return Err(Error::InvalidParams(
                "o mínimo de guardiões não bate com a lista".into(),
            ));
        }
        if members.contains_key(&0) {
            return Err(Error::InvalidParams("o guardião 0 não existe".into()));
        }
        let guardians = Guardians {
            version: file.version,
            threshold: file.threshold,
            public_key: decode_point(&file.public_key)?,
            members,
        };
        guardians.check_consistent()?;
        Ok(guardians)
    }

    /// As chaves de conferência precisam sair de um mesmo polinômio de grau
    /// `threshold - 1`, e a chave pública precisa ser o valor dele no zero.
    /// Senão, um arquivo trocado faria a rede selar para outra chave enquanto
    /// as partes dos guardiões continuam conferindo.
    pub fn check_consistent(&self) -> Result<(), Error> {
        let base: BTreeSet<u8> = self
            .members
            .keys()
            .take(usize::from(self.threshold))
            .copied()
            .collect();
        let at = |x: u8| -> RistrettoPoint {
            base.iter()
                .map(|index| lagrange_at(x, *index, &base) * self.members[index].verification_key)
                .sum()
        };

        if at(0) != self.public_key {
            return Err(Error::InvalidParams(
                "a chave pública não sai das chaves de conferência".into(),
            ));
        }
        for (index, member) in &self.members {
            if !base.contains(index) && at(*index) != member.verification_key {
                return Err(Error::InvalidParams(format!(
                    "a chave de conferência do guardião {index} não bate com as outras"
                )));
            }
        }
        Ok(())
    }

    pub fn to_toml_string(&self) -> String {
        let file = GuardiansFile {
            version: self.version,
            threshold: self.threshold,
            public_key: encode_point(&self.public_key),
            guardians: self
                .members
                .iter()
                .map(|(index, member)| MemberFile {
                    index: *index,
                    name: member.name.clone(),
                    verification_key: encode_point(&member.verification_key),
                })
                .collect(),
        };
        toml::to_string(&file).expect("os parâmetros sempre viram TOML")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn names() -> Vec<String> {
        (1..=5).map(|index| format!("Guardião {index}")).collect()
    }

    fn setup() -> Ceremony {
        ceremony(3, 5, &names()).unwrap()
    }

    fn partials(
        ceremony: &Ceremony,
        sealed: &Sealed,
        context: &[u8],
        indices: &[u8],
    ) -> Vec<Partial> {
        indices
            .iter()
            .map(|index| {
                partial(&ceremony.shares[usize::from(index - 1)], sealed, context).unwrap()
            })
            .collect()
    }

    #[test]
    fn any_three_of_five_open() {
        let ceremony = setup();
        let sealed = seal(
            &ceremony.guardians.public_key,
            b"52998224725",
            b"cpf:conta-1",
        );

        for trio in [[1, 2, 3], [1, 3, 5], [2, 4, 5], [3, 4, 5]] {
            let opened = open(
                &ceremony.guardians,
                &sealed,
                &partials(&ceremony, &sealed, b"cpf:conta-1", &trio),
                b"cpf:conta-1",
            );
            assert_eq!(opened.unwrap(), b"52998224725", "trio {trio:?}");
        }
    }

    #[test]
    fn two_are_not_enough() {
        let ceremony = setup();
        let sealed = seal(
            &ceremony.guardians.public_key,
            b"52998224725",
            b"cpf:conta-1",
        );
        let result = open(
            &ceremony.guardians,
            &sealed,
            &partials(&ceremony, &sealed, b"cpf:conta-1", &[1, 4]),
            b"cpf:conta-1",
        );
        assert_eq!(result, Err(Error::NotEnoughPartials { needed: 3, got: 2 }));
    }

    #[test]
    fn the_same_guardian_twice_counts_once() {
        let ceremony = setup();
        let sealed = seal(&ceremony.guardians.public_key, b"x", b"ctx");
        let result = open(
            &ceremony.guardians,
            &sealed,
            &partials(&ceremony, &sealed, b"ctx", &[2, 2, 2]),
            b"ctx",
        );
        assert_eq!(result, Err(Error::NotEnoughPartials { needed: 3, got: 1 }));
    }

    #[test]
    fn a_forged_partial_is_refused() {
        let ceremony = setup();
        let sealed = seal(&ceremony.guardians.public_key, b"x", b"ctx");
        let mut forged = partial(&ceremony.shares[0], &sealed, b"ctx").unwrap();
        forged.point += G;

        assert_eq!(
            verify_partial(&ceremony.guardians, &sealed, &forged),
            Err(Error::BadProof(1))
        );
    }

    #[test]
    fn a_partial_for_one_cpf_does_not_open_another() {
        let ceremony = setup();
        let first = seal(&ceremony.guardians.public_key, b"111", b"cpf:a");
        let second = seal(&ceremony.guardians.public_key, b"222", b"cpf:b");
        let for_first = partials(&ceremony, &first, b"cpf:a", &[1, 2, 3]);

        assert!(open(&ceremony.guardians, &second, &for_first, b"cpf:b").is_err());
    }

    #[test]
    fn a_sealed_cpf_copied_to_another_account_does_not_open() {
        let ceremony = setup();
        let sealed = seal(
            &ceremony.guardians.public_key,
            b"52998224725",
            b"cpf:conta-1",
        );

        // O guardião recusa calcular a parte com o contexto de outra conta.
        assert_eq!(
            partial(&ceremony.shares[0], &sealed, b"cpf:conta-2").err(),
            Some(Error::BadSealed)
        );
        let result = open(
            &ceremony.guardians,
            &sealed,
            &partials(&ceremony, &sealed, b"cpf:conta-1", &[1, 2, 3]),
            b"cpf:conta-2",
        );
        assert_eq!(result, Err(Error::BadSealed));
    }

    #[test]
    fn a_blinded_sealed_from_another_account_is_refused() {
        // A rede tenta abrir a conta B pedindo a parte para k·R_B, com o
        // contexto da conta A. Sem conhecer k·r, não há prova que confira.
        let ceremony = setup();
        let target = seal(&ceremony.guardians.public_key, b"222", b"cpf:b");
        let k = Scalar::random(&mut OsRng);

        let blinded = Sealed {
            ephemeral: k * target.ephemeral,
            ephemeral_h: k * target.ephemeral_h,
            challenge: target.challenge,
            response: k * target.response,
            nonce: target.nonce,
            ciphertext: target.ciphertext.clone(),
        };
        for context in [&b"cpf:a"[..], &b"cpf:b"[..]] {
            assert_eq!(
                partial(&ceremony.shares[0], &blinded, context).err(),
                Some(Error::BadSealed)
            );
        }
    }

    #[test]
    fn a_bad_partial_does_not_block_the_others() {
        let ceremony = setup();
        let sealed = seal(&ceremony.guardians.public_key, b"52998224725", b"ctx");
        let mut given = partials(&ceremony, &sealed, b"ctx", &[1, 2, 3, 4]);
        given[0].point += G;

        let opened = open(&ceremony.guardians, &sealed, &given, b"ctx");
        assert_eq!(opened.unwrap(), b"52998224725");

        let two_good = &given[..3];
        assert_eq!(
            open(&ceremony.guardians, &sealed, two_good, b"ctx"),
            Err(Error::NotEnoughPartials { needed: 3, got: 2 })
        );
    }

    #[test]
    fn guardians_file_must_hold_together() {
        let ceremony = setup();
        let good = ceremony.guardians.to_toml_string();

        let mut other_key = ceremony.guardians.clone();
        other_key.public_key += G;
        assert!(Guardians::from_toml_str(&other_key.to_toml_string()).is_err());

        let mut other_member = ceremony.guardians.clone();
        other_member.members.get_mut(&5).unwrap().verification_key += G;
        assert!(Guardians::from_toml_str(&other_member.to_toml_string()).is_err());

        assert!(Guardians::from_toml_str(&good).is_ok());
    }

    #[test]
    fn files_round_trip() {
        let ceremony = setup();
        let guardians = Guardians::from_toml_str(&ceremony.guardians.to_toml_string()).unwrap();
        assert_eq!(guardians, ceremony.guardians);

        let sealed = seal(&guardians.public_key, b"texto", b"ctx");
        assert_eq!(Sealed::from_base64(&sealed.to_base64()).unwrap(), sealed);

        let share = Share::from_file(&ceremony.shares[2].to_file()).unwrap();
        let wire = PartialWire::from(&partial(&share, &sealed, b"ctx").unwrap());
        let back = Partial::try_from(&wire).unwrap();
        assert!(verify_partial(&guardians, &sealed, &back).is_ok());
    }

    #[test]
    fn ceremony_rejects_weak_thresholds() {
        assert!(ceremony(1, 5, &names()).is_err());
        assert!(ceremony(6, 5, &names()).is_err());
    }
}
