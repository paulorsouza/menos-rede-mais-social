use serde::Deserialize;

/// Parâmetros públicos do feed, lidos de `params/feed.toml`.
#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Params {
    pub version: u32,
    pub recency: Recency,
    pub bubble: Bubble,
    pub outside_bubble: OutsideBubble,
    pub mixed: Mixed,
    pub public_ranking: PublicRanking,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Recency {
    pub half_life_hours: u32,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Bubble {
    pub follow_weight: i64,
    pub topic_weight: i64,
    pub engagement_weight: i64,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct OutsideBubble {
    pub max_interest: u32,
    pub min_engagement: u32,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Mixed {
    pub outside_every: usize,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PublicRanking {
    pub like_weight: i64,
    pub save_weight: i64,
}

impl Params {
    pub fn from_toml_str(source: &str) -> Result<Self, toml::de::Error> {
        toml::from_str(source)
    }
}
