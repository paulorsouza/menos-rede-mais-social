//! Registro público da -rede+social.
//!
//! Uma árvore de Merkle que só aceita acréscimos, no formato do Certificate
//! Transparency (RFC 6962 e RFC 9162). Cada entrada é um texto curto: uma
//! versão do motor com o hash dos parâmetros, a raiz diária dos dados, a
//! abertura de uma ordem judicial. A rede publica o cabeçalho da árvore
//! (tamanho e raiz) assinado, e qualquer pessoa consegue provar duas coisas
//! sem confiar na rede:
//!
//! - **Inclusão:** uma entrada está mesmo na árvore daquele cabeçalho.
//! - **Consistência:** a árvore de hoje é a de ontem com coisas a mais. Se
//!   alguém apagar ou trocar uma entrada antiga, a prova não fecha.
//!
//! Este crate é usado pelo verificador aberto. O backend, que mantém o
//! registro, calcula as mesmas coisas em Elixir, e os testes dos dois lados
//! conferem os mesmos valores.

use ed25519_dalek::{Signature, Verifier, VerifyingKey};
use sha2::{Digest, Sha256};

pub type Hash = [u8; 32];

/// Hash de uma folha: SHA-256(0x00 || dados).
pub fn leaf_hash(data: &[u8]) -> Hash {
    let mut hash = Sha256::new();
    hash.update([0u8]);
    hash.update(data);
    hash.finalize().into()
}

/// Hash de um nó interno: SHA-256(0x01 || esquerda || direita).
pub fn node_hash(left: &Hash, right: &Hash) -> Hash {
    let mut hash = Sha256::new();
    hash.update([1u8]);
    hash.update(left);
    hash.update(right);
    hash.finalize().into()
}

/// Maior potência de 2 menor que `n` (n > 1).
fn split(n: usize) -> usize {
    let mut k = 1;
    while k << 1 < n {
        k <<= 1;
    }
    k
}

/// Raiz da árvore com estas folhas (já em hash).
pub fn root(leaves: &[Hash]) -> Hash {
    match leaves.len() {
        0 => Sha256::digest([]).into(),
        1 => leaves[0],
        n => {
            let k = split(n);
            node_hash(&root(&leaves[..k]), &root(&leaves[k..]))
        }
    }
}

/// Prova de que a folha `index` está na árvore `leaves`.
pub fn inclusion_proof(leaves: &[Hash], index: usize) -> Vec<Hash> {
    let n = leaves.len();
    if n <= 1 {
        return Vec::new();
    }
    let k = split(n);
    if index < k {
        let mut proof = inclusion_proof(&leaves[..k], index);
        proof.push(root(&leaves[k..]));
        proof
    } else {
        let mut proof = inclusion_proof(&leaves[k..], index - k);
        proof.push(root(&leaves[..k]));
        proof
    }
}

/// Confere uma prova de inclusão (RFC 9162, seção 2.1.3.2).
pub fn verify_inclusion(leaf: &Hash, index: u64, size: u64, proof: &[Hash], root: &Hash) -> bool {
    if index >= size {
        return false;
    }
    let (mut fn_, mut sn) = (index, size - 1);
    let mut result = *leaf;
    for sibling in proof {
        if sn == 0 {
            return false;
        }
        if fn_ & 1 == 1 || fn_ == sn {
            result = node_hash(sibling, &result);
            while fn_ & 1 == 0 && fn_ != 0 {
                fn_ >>= 1;
                sn >>= 1;
            }
        } else {
            result = node_hash(&result, sibling);
        }
        fn_ >>= 1;
        sn >>= 1;
    }
    sn == 0 && result == *root
}

/// Prova de que a árvore com as primeiras `old_size` folhas é o começo da
/// árvore com todas as folhas.
pub fn consistency_proof(leaves: &[Hash], old_size: usize) -> Vec<Hash> {
    if old_size == 0 || old_size >= leaves.len() {
        return Vec::new();
    }
    subproof(old_size, leaves, true)
}

fn subproof(m: usize, leaves: &[Hash], complete: bool) -> Vec<Hash> {
    let n = leaves.len();
    if m == n {
        return if complete {
            Vec::new()
        } else {
            vec![root(leaves)]
        };
    }
    let k = split(n);
    if m <= k {
        let mut proof = subproof(m, &leaves[..k], complete);
        proof.push(root(&leaves[k..]));
        proof
    } else {
        let mut proof = subproof(m - k, &leaves[k..], false);
        proof.push(root(&leaves[..k]));
        proof
    }
}

/// Confere uma prova de consistência (RFC 9162, seção 2.1.4.2).
pub fn verify_consistency(
    old_size: u64,
    new_size: u64,
    old_root: &Hash,
    new_root: &Hash,
    proof: &[Hash],
) -> bool {
    if old_size > new_size {
        return false;
    }
    if old_size == new_size {
        return proof.is_empty() && old_root == new_root;
    }
    if old_size == 0 {
        return proof.is_empty();
    }
    if proof.is_empty() {
        return false;
    }

    let mut path: Vec<Hash> = proof.to_vec();
    if old_size.is_power_of_two() {
        path.insert(0, *old_root);
    }

    let (mut fn_, mut sn) = (old_size - 1, new_size - 1);
    while fn_ & 1 == 1 {
        fn_ >>= 1;
        sn >>= 1;
    }

    let (mut fr, mut sr) = (path[0], path[0]);
    for c in &path[1..] {
        if sn == 0 {
            return false;
        }
        if fn_ & 1 == 1 || fn_ == sn {
            fr = node_hash(c, &fr);
            sr = node_hash(c, &sr);
            while fn_ & 1 == 0 && fn_ != 0 {
                fn_ >>= 1;
                sn >>= 1;
            }
        } else {
            sr = node_hash(&sr, c);
        }
        fn_ >>= 1;
        sn >>= 1;
    }
    fr == *old_root && sr == *new_root && sn == 0
}

/// O cabeçalho da árvore num momento: tamanho, raiz e quando foi assinado.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TreeHead {
    pub size: u64,
    pub root: Hash,
    /// Segundos Unix.
    pub timestamp: i64,
}

impl TreeHead {
    /// O texto exato que a rede assina.
    pub fn signed_message(&self) -> String {
        format!(
            "registro -rede+social v1\n{}\n{}\n{}\n",
            self.size,
            hex::encode(self.root),
            self.timestamp
        )
    }

    /// Confere a assinatura Ed25519 do cabeçalho com a chave pública do registro.
    pub fn verify(&self, public_key: &[u8; 32], signature: &[u8; 64]) -> bool {
        let Ok(key) = VerifyingKey::from_bytes(public_key) else {
            return false;
        };
        key.verify(
            self.signed_message().as_bytes(),
            &Signature::from_bytes(signature),
        )
        .is_ok()
    }
}

pub fn parse_hash(text: &str) -> Option<Hash> {
    hex::decode(text).ok()?.try_into().ok()
}

#[cfg(test)]
mod tests {
    use super::*;
    use ed25519_dalek::{Signer, SigningKey};

    fn leaves(n: usize) -> Vec<Hash> {
        (0..n)
            .map(|i| leaf_hash(format!("entrada {i}").as_bytes()))
            .collect()
    }

    #[test]
    fn empty_and_single_trees() {
        assert_eq!(
            hex::encode(root(&[])),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        );
        let one = leaves(1);
        assert_eq!(root(&one), one[0]);
    }

    /// Mesmos valores do teste do backend (RedeSocial.Registro.MerkleTest): os
    /// dois lados calculam a mesma árvore.
    #[test]
    fn matches_the_backend() {
        assert_eq!(
            hex::encode(root(&leaves(7))),
            "ea6dc9e12718639df89c0af5a185c7ec79f30e0d3f054b503531590e2513c6eb"
        );
    }

    #[test]
    fn every_inclusion_proof_checks_out() {
        for n in 1..=33 {
            let tree = leaves(n);
            let top = root(&tree);
            for i in 0..n {
                let proof = inclusion_proof(&tree, i);
                assert!(
                    verify_inclusion(&tree[i], i as u64, n as u64, &proof, &top),
                    "n={n} i={i}"
                );
                assert!(!verify_inclusion(
                    &leaf_hash(b"outra"),
                    i as u64,
                    n as u64,
                    &proof,
                    &top
                ));
            }
        }
    }

    #[test]
    fn every_consistency_proof_checks_out() {
        for n in 1..=33 {
            let tree = leaves(n);
            for m in 1..=n {
                let proof = consistency_proof(&tree, m);
                assert!(
                    verify_consistency(m as u64, n as u64, &root(&tree[..m]), &root(&tree), &proof),
                    "m={m} n={n}"
                );
            }
        }
    }

    #[test]
    fn rewriting_history_breaks_consistency() {
        let honest = leaves(10);
        let mut rewritten = honest.clone();
        rewritten[3] = leaf_hash(b"entrada trocada");

        let proof = consistency_proof(&rewritten, 6);
        assert!(!verify_consistency(
            6,
            10,
            &root(&honest[..6]),
            &root(&rewritten),
            &proof
        ));
    }

    #[test]
    fn tree_heads_are_signed() {
        let key = SigningKey::from_bytes(&[7u8; 32]);
        let head = TreeHead {
            size: 10,
            root: root(&leaves(10)),
            timestamp: 1_800_000_000,
        };
        let signature = key.sign(head.signed_message().as_bytes()).to_bytes();
        let public = key.verifying_key().to_bytes();

        assert!(head.verify(&public, &signature));
        let tampered = TreeHead { size: 9, ..head };
        assert!(!tampered.verify(&public, &signature));
    }
}
