use serde::{Deserialize, Serialize};

/// Parâmetros públicos do feed, lidos de `params/feed.toml`.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Params {
    pub version: u32,
    pub recency: Recency,
    pub graph: Graph,
    pub neighbors: Neighbors,
    pub bubble: Bubble,
    pub outside_bubble: OutsideBubble,
    pub mixed: Mixed,
    pub public_ranking: PublicRanking,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Recency {
    pub half_life_hours: u32,
}

/// Quais ligações entre pessoas e posts contam, e quanto cada uma vale.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Graph {
    pub window_days: u32,
    pub watch_min_seconds: u32,
    pub like_weight: u32,
    pub watch_weight: u32,
}

/// Quem conta como alguém de gosto parecido.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Neighbors {
    pub min_shared: u32,
    pub min_overlap_percent: u32,
    pub max_neighbors: usize,
    pub follow_weight: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Bubble {
    pub author_points: i64,
    pub engagement_weight: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct OutsideBubble {
    pub min_engagement: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Mixed {
    pub outside_every: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
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
