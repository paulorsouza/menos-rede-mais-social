//! Recibo do feed.
//!
//! Cada vez que o motor ordena um feed, ele assina um recibo que liga três
//! coisas: a entrada exata que recebeu, a saída que devolveu e o hash dos
//! parâmetros que usou, junto com a versão do motor. Com o recibo, a entrada
//! e o arquivo de parâmetros, qualquer pessoa refaz a conta com este mesmo
//! código e confere que a saída bate.
//!
//! A entrada e a saída viram bytes sempre do mesmo jeito: a serialização JSON
//! das estruturas deste crate, campo por campo na ordem em que estão
//! declaradas. Por isso o verificador usa estas mesmas estruturas.

use ed25519_dalek::{Signature, Verifier, VerifyingKey};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::{Candidate, Edge, FeedMode, RankedItem, Viewer};

/// O que o motor recebe para ordenar um feed.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RankInput {
    pub mode: FeedMode,
    pub viewer: Viewer,
    pub candidates: Vec<Candidate>,
    /// Quem curtiu e assistiu o quê: o grafo de onde sai o feed.
    #[serde(default)]
    pub edges: Vec<Edge>,
    pub now: i64,
}

impl RankInput {
    pub fn sha256(&self) -> String {
        hex::encode(Sha256::digest(
            serde_json::to_vec(self).expect("a entrada sempre vira JSON"),
        ))
    }
}

pub fn output_sha256(items: &[RankedItem]) -> String {
    hex::encode(Sha256::digest(
        serde_json::to_vec(items).expect("a saída sempre vira JSON"),
    ))
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Receipt {
    pub input_sha256: String,
    pub output_sha256: String,
    pub params_sha256: String,
    pub engine_version: String,
    pub engine_build: String,
    pub now: i64,
    /// Assinatura Ed25519, em base64.
    pub signature: String,
}

impl Receipt {
    /// O texto exato que o motor assina.
    pub fn signed_message(&self) -> String {
        format!(
            "recibo -rede+social v1\n{}\n{}\n{}\n{}\n{}\n{}\n",
            self.input_sha256,
            self.output_sha256,
            self.params_sha256,
            self.engine_version,
            self.engine_build,
            self.now
        )
    }

    pub fn verify(&self, public_key: &[u8; 32]) -> bool {
        use base64::{Engine as _, engine::general_purpose::STANDARD};

        let Ok(key) = VerifyingKey::from_bytes(public_key) else {
            return false;
        };
        let Ok(bytes) = STANDARD.decode(&self.signature) else {
            return false;
        };
        let Ok(signature) = <[u8; 64]>::try_from(bytes.as_slice()) else {
            return false;
        };
        key.verify(
            self.signed_message().as_bytes(),
            &Signature::from_bytes(&signature),
        )
        .is_ok()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use base64::{Engine as _, engine::general_purpose::STANDARD};
    use ed25519_dalek::{Signer, SigningKey};

    const INPUT: &str = r#"{"mode":"bubble","viewer":{"id":9,"follows":[1]},"candidates":[{"post_id":5,"author_id":1,"created_at":10,"likes":2,"saves":0}],"edges":[],"now":20}"#;
    const SAME_INPUT_OTHER_ORDER: &str = r#"{"now":20,"edges":[],"viewer":{"follows":[1],"id":9},"mode":"bubble","candidates":[{"saves":0,"likes":2,"created_at":10,"author_id":1,"post_id":5}]}"#;

    #[test]
    fn the_input_hash_does_not_depend_on_how_the_json_was_written() {
        let a: RankInput = serde_json::from_str(INPUT).unwrap();
        let b: RankInput = serde_json::from_str(SAME_INPUT_OTHER_ORDER).unwrap();
        assert_eq!(a.sha256(), b.sha256());
    }

    #[test]
    fn a_receipt_only_checks_out_with_the_engine_key_and_untouched() {
        let key = SigningKey::from_bytes(&[3u8; 32]);
        let input: RankInput = serde_json::from_str(INPUT).unwrap();
        let mut receipt = Receipt {
            input_sha256: input.sha256(),
            output_sha256: output_sha256(&[]),
            params_sha256: "abc".into(),
            engine_version: "0.1.0".into(),
            engine_build: "dev".into(),
            now: input.now,
            signature: String::new(),
        };
        receipt.signature =
            STANDARD.encode(key.sign(receipt.signed_message().as_bytes()).to_bytes());

        assert!(receipt.verify(&key.verifying_key().to_bytes()));
        assert!(
            !receipt.verify(
                &SigningKey::from_bytes(&[4u8; 32])
                    .verifying_key()
                    .to_bytes()
            )
        );

        let tampered = Receipt {
            output_sha256: "outra".into(),
            ..receipt
        };
        assert!(!tampered.verify(&key.verifying_key().to_bytes()));
    }
}
