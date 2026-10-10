use std::fmt;

use serde::{Deserialize, Serialize};

/// Parâmetros públicos de anúncios, lidos de `params/ads.toml`.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Params {
    pub version: u32,
    pub shorts_ad_every: u32,
    pub payout: Payout,
    pub pricing: Pricing,
    pub antifraud: Antifraud,
    pub delivery: Delivery,
    pub payout_bands: Vec<PayoutBand>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Payout {
    /// Centavos por mil views com anúncio, na primeira faixa.
    pub base_cents_per_thousand: u64,
    /// Quanto vale uma view com anúncio regional, em porcentagem da nacional.
    pub regional_view_percent: u32,
    /// Parte da receita de cada anúncio dos shorts que vai para os criadores.
    pub creator_share_percent: u32,
    /// Abaixo disso, o repasse fica para o mês seguinte.
    pub minimum_payout_cents: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Pricing {
    pub ad_seconds: u64,
    pub national_cents_per_impression: u64,
    pub regional_cents_per_impression: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Antifraud {
    pub max_views_per_viewer_post_per_day: u32,
    pub max_views_per_viewer_creator_per_day: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Delivery {
    /// Um peso por hora do dia, da 0h às 23h (hora de Brasília).
    pub hourly_weights: Vec<u32>,
    pub headroom_percent: u32,
    pub region_headroom_percent: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PayoutBand {
    /// Limite de cima da faixa, em views no mês. `None` só na última faixa.
    pub up_to: Option<u64>,
    /// Quanto do valor base cada view desta faixa paga, de 0 a 100.
    pub percent: u32,
}

#[derive(Debug)]
pub enum ParamsError {
    Toml(toml::de::Error),
    Invalid(&'static str),
}

impl fmt::Display for ParamsError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ParamsError::Toml(error) => write!(f, "arquivo de parâmetros inválido: {error}"),
            ParamsError::Invalid(reason) => write!(f, "parâmetros inválidos: {reason}"),
        }
    }
}

impl std::error::Error for ParamsError {}

impl Params {
    pub fn from_toml_str(source: &str) -> Result<Self, ParamsError> {
        let params: Params = toml::from_str(source).map_err(ParamsError::Toml)?;
        params.validate()?;
        Ok(params)
    }

    fn validate(&self) -> Result<(), ParamsError> {
        use ParamsError::Invalid;

        if self.shorts_ad_every == 0 {
            return Err(Invalid("shorts_ad_every precisa ser maior que zero"));
        }
        if self.payout.regional_view_percent > 100 || self.payout.creator_share_percent > 100 {
            return Err(Invalid("porcentagens vão de 0 a 100"));
        }
        if self.pricing.ad_seconds == 0 {
            return Err(Invalid("ad_seconds precisa ser maior que zero"));
        }
        if self.antifraud.max_views_per_viewer_post_per_day == 0
            || self.antifraud.max_views_per_viewer_creator_per_day == 0
        {
            return Err(Invalid(
                "os limites do antifraude precisam ser maiores que zero",
            ));
        }
        if self.delivery.hourly_weights.len() != 24
            || self
                .delivery
                .hourly_weights
                .iter()
                .all(|&weight| weight == 0)
        {
            return Err(Invalid(
                "hourly_weights precisa ter 24 pesos, e nem todos zero",
            ));
        }

        let Some((last, others)) = self.payout_bands.split_last() else {
            return Err(Invalid("é preciso pelo menos uma faixa de pagamento"));
        };
        if last.up_to.is_some() {
            return Err(Invalid("a última faixa não pode ter limite (up_to)"));
        }

        let mut previous_limit = 0;
        for band in others {
            let Some(limit) = band.up_to else {
                return Err(Invalid("só a última faixa pode ficar sem limite"));
            };
            if limit <= previous_limit {
                return Err(Invalid("os limites das faixas precisam crescer"));
            }
            previous_limit = limit;
        }

        let mut previous_percent = 100;
        for band in &self.payout_bands {
            if band.percent > previous_percent {
                return Err(Invalid(
                    "o percentual não pode subir de uma faixa para a seguinte",
                ));
            }
            previous_percent = band.percent;
        }

        Ok(())
    }
}
