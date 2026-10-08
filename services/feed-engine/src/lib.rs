//! Motor de feed da -rede+social.
//!
//! Todos os modos são determinísticos: com os mesmos dados de entrada, os mesmos
//! parâmetros (`params/feed.toml`) e a mesma versão do código, o resultado é
//! sempre o mesmo. É isso que permite a qualquer pessoa refazer o cálculo do
//! feed de alguém e conferir que a rede seguiu as regras publicadas.
//!
//! As contas usam só inteiros, para o resultado não variar de uma máquina para
//! outra.

mod params;

use std::collections::{BTreeMap, BTreeSet};

pub use params::Params;

pub type PostId = u64;
pub type UserId = u64;

/// Pontuação de recência de um post recém-publicado.
const RECENCY_MAX: i64 = 1024;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FeedMode {
    /// Na bolha: quem você segue e os temas de que você gosta.
    Bubble,
    /// Furando a bolha: conteúdo bem avaliado de temas longe do seu perfil.
    OutsideBubble,
    /// Meio a meio: os dois modos acima, intercalados.
    Mixed,
    /// Sem algoritmo: só quem você segue, do mais novo para o mais antigo.
    Chronological,
    /// Sem algoritmo: uma fórmula pública, igual para todo mundo.
    PublicRanking,
}

/// Um post que pode entrar no feed.
#[derive(Debug, Clone)]
pub struct Candidate {
    pub post_id: PostId,
    pub author_id: UserId,
    /// Segundos desde 1970 (horário Unix).
    pub created_at: i64,
    pub topics: Vec<String>,
    pub likes: u32,
    pub saves: u32,
}

/// O que o motor sabe sobre quem está vendo o feed.
#[derive(Debug, Clone, Default)]
pub struct Viewer {
    pub follows: BTreeSet<UserId>,
    /// Peso de cada tema, de 0 a 100. A pessoa vê e edita esses pesos no app.
    pub interests: BTreeMap<String, u32>,
}

/// Por que um post apareceu no feed. Vai junto com cada item até a tela.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Reason {
    YouFollow,
    Topic(String),
    OutsideBubble(String),
    PublicRanking,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RankedItem {
    pub post_id: PostId,
    pub score: i64,
    pub reasons: Vec<Reason>,
}

pub fn rank(
    mode: FeedMode,
    viewer: &Viewer,
    candidates: &[Candidate],
    params: &Params,
    now: i64,
) -> Vec<RankedItem> {
    match mode {
        FeedMode::Bubble => bubble(viewer, candidates, params, now),
        FeedMode::OutsideBubble => outside_bubble(viewer, candidates, params, now),
        FeedMode::Mixed => mixed(viewer, candidates, params, now),
        FeedMode::Chronological => chronological(viewer, candidates),
        FeedMode::PublicRanking => public_ranking(candidates, params, now),
    }
}

/// Cai pela metade a cada `half_life_hours`. Um post com data no futuro
/// (relógio adiantado) conta como recém-publicado.
fn recency(created_at: i64, now: i64, params: &Params) -> i64 {
    let age_hours = (now - created_at).max(0) / 3600;
    let half_life = i64::from(params.recency.half_life_hours.max(1));
    let halvings = age_hours / half_life;
    if halvings >= 63 {
        0
    } else {
        RECENCY_MAX >> halvings
    }
}

fn engagement(candidate: &Candidate) -> i64 {
    i64::from(candidate.likes) + i64::from(candidate.saves)
}

fn interest(viewer: &Viewer, topic: &str) -> u32 {
    viewer.interests.get(topic).copied().unwrap_or(0)
}

/// Um tema está "dentro da bolha" quando o interesse passa do limite usado
/// pelo modo furando a bolha. Assim os dois modos nunca disputam o mesmo post.
fn bubble(viewer: &Viewer, candidates: &[Candidate], params: &Params, now: i64) -> Vec<RankedItem> {
    let weights = &params.bubble;
    let threshold = params.outside_bubble.max_interest;

    let mut items: Vec<RankedItem> = candidates
        .iter()
        .filter_map(|candidate| {
            let mut relevance = 0;
            let mut reasons = Vec::new();

            if viewer.follows.contains(&candidate.author_id) {
                relevance += weights.follow_weight;
                reasons.push(Reason::YouFollow);
            }
            for topic in &candidate.topics {
                let weight = interest(viewer, topic);
                if weight > threshold {
                    relevance += weights.topic_weight * i64::from(weight);
                    reasons.push(Reason::Topic(topic.clone()));
                }
            }
            if reasons.is_empty() {
                return None;
            }

            relevance += weights.engagement_weight * engagement(candidate);
            Some(RankedItem {
                post_id: candidate.post_id,
                score: relevance * recency(candidate.created_at, now, params),
                reasons,
            })
        })
        .collect();

    sort_by_score(&mut items);
    items
}

fn outside_bubble(
    viewer: &Viewer,
    candidates: &[Candidate],
    params: &Params,
    now: i64,
) -> Vec<RankedItem> {
    let rules = &params.outside_bubble;

    let mut items: Vec<RankedItem> = candidates
        .iter()
        .filter(|candidate| {
            !viewer.follows.contains(&candidate.author_id)
                && !candidate.topics.is_empty()
                && candidate
                    .topics
                    .iter()
                    .all(|topic| interest(viewer, topic) <= rules.max_interest)
                && engagement(candidate) >= i64::from(rules.min_engagement)
        })
        .map(|candidate| RankedItem {
            post_id: candidate.post_id,
            score: engagement(candidate) * recency(candidate.created_at, now, params),
            reasons: candidate
                .topics
                .iter()
                .cloned()
                .map(Reason::OutsideBubble)
                .collect(),
        })
        .collect();

    sort_by_score(&mut items);
    items
}

/// Intercala os dois modos: a cada `outside_every` posições, uma vem de fora
/// da bolha. Quando um dos lados acaba, o outro completa o feed.
fn mixed(viewer: &Viewer, candidates: &[Candidate], params: &Params, now: i64) -> Vec<RankedItem> {
    let every = params.mixed.outside_every.max(1);
    let mut inside = bubble(viewer, candidates, params, now).into_iter();
    let mut outside = outside_bubble(viewer, candidates, params, now).into_iter();

    let mut items = Vec::new();
    loop {
        let outside_turn = (items.len() + 1) % every == 0;
        let next = if outside_turn {
            outside.next().or_else(|| inside.next())
        } else {
            inside.next().or_else(|| outside.next())
        };
        match next {
            Some(item) => items.push(item),
            None => return items,
        }
    }
}

fn chronological(viewer: &Viewer, candidates: &[Candidate]) -> Vec<RankedItem> {
    let mut items: Vec<RankedItem> = candidates
        .iter()
        .filter(|candidate| viewer.follows.contains(&candidate.author_id))
        .map(|candidate| RankedItem {
            post_id: candidate.post_id,
            score: candidate.created_at,
            reasons: vec![Reason::YouFollow],
        })
        .collect();

    sort_by_score(&mut items);
    items
}

fn public_ranking(candidates: &[Candidate], params: &Params, now: i64) -> Vec<RankedItem> {
    let weights = &params.public_ranking;

    let mut items: Vec<RankedItem> = candidates
        .iter()
        .map(|candidate| {
            let points = weights.like_weight * i64::from(candidate.likes)
                + weights.save_weight * i64::from(candidate.saves)
                + 1;
            RankedItem {
                post_id: candidate.post_id,
                score: points * recency(candidate.created_at, now, params),
                reasons: vec![Reason::PublicRanking],
            }
        })
        .collect();

    sort_by_score(&mut items);
    items
}

/// Maior pontuação primeiro. O empate é decidido pelo id do post, para o
/// resultado nunca depender da ordem em que os candidatos chegaram.
fn sort_by_score(items: &mut [RankedItem]) {
    items.sort_by(|a, b| b.score.cmp(&a.score).then(a.post_id.cmp(&b.post_id)));
}

#[cfg(test)]
mod tests {
    use super::*;

    const HOUR: i64 = 3600;
    const NOW: i64 = 1_800_000_000;

    fn params() -> Params {
        Params::from_toml_str(include_str!("../../../params/feed.toml"))
            .expect("params/feed.toml precisa ser válido")
    }

    fn post(
        post_id: PostId,
        author_id: UserId,
        hours_ago: i64,
        topics: &[&str],
        likes: u32,
        saves: u32,
    ) -> Candidate {
        Candidate {
            post_id,
            author_id,
            created_at: NOW - hours_ago * HOUR,
            topics: topics.iter().map(|topic| topic.to_string()).collect(),
            likes,
            saves,
        }
    }

    /// Segue o usuário 1, gosta muito de futebol e quase nada de culinária.
    fn viewer() -> Viewer {
        Viewer {
            follows: BTreeSet::from([1]),
            interests: BTreeMap::from([("futebol".to_string(), 80), ("culinaria".to_string(), 5)]),
        }
    }

    fn ids(items: &[RankedItem]) -> Vec<PostId> {
        items.iter().map(|item| item.post_id).collect()
    }

    #[test]
    fn public_params_file_is_valid() {
        assert_eq!(params().version, 1);
    }

    #[test]
    fn recency_halves_every_half_life() {
        let params = params();
        assert_eq!(recency(NOW, NOW, &params), 1024);
        assert_eq!(recency(NOW - 24 * HOUR, NOW, &params), 512);
        assert_eq!(recency(NOW - 48 * HOUR, NOW, &params), 256);
        assert_eq!(recency(NOW + HOUR, NOW, &params), 1024);
    }

    #[test]
    fn chronological_shows_only_follows_newest_first() {
        let candidates = [
            post(10, 1, 5, &[], 0, 0),
            post(11, 2, 1, &["futebol"], 50, 0),
            post(12, 1, 1, &[], 0, 0),
        ];
        let feed = rank(
            FeedMode::Chronological,
            &viewer(),
            &candidates,
            &params(),
            NOW,
        );
        assert_eq!(ids(&feed), [12, 10]);
    }

    #[test]
    fn bubble_explains_why_each_post_appears() {
        let candidates = [
            post(20, 1, 1, &["politica"], 0, 0),
            post(21, 3, 1, &["futebol"], 0, 0),
            post(22, 3, 1, &["culinaria"], 0, 0),
        ];
        let feed = rank(FeedMode::Bubble, &viewer(), &candidates, &params(), NOW);
        assert_eq!(ids(&feed), [20, 21]);
        assert_eq!(feed[0].reasons, [Reason::YouFollow]);
        assert_eq!(feed[1].reasons, [Reason::Topic("futebol".into())]);
    }

    #[test]
    fn outside_bubble_skips_follows_and_known_topics() {
        let candidates = [
            post(30, 1, 1, &["astronomia"], 100, 0),
            post(31, 3, 1, &["futebol"], 100, 0),
            post(32, 3, 1, &["astronomia"], 5, 0),
            post(33, 3, 1, &["astronomia"], 30, 0),
            post(34, 4, 1, &["culinaria"], 40, 0),
        ];
        let feed = rank(
            FeedMode::OutsideBubble,
            &viewer(),
            &candidates,
            &params(),
            NOW,
        );
        assert_eq!(ids(&feed), [34, 33]);
        assert_eq!(
            feed[1].reasons,
            [Reason::OutsideBubble("astronomia".into())]
        );
    }

    #[test]
    fn mixed_alternates_inside_and_outside() {
        let candidates = [
            post(40, 1, 1, &[], 0, 0),
            post(41, 1, 2, &[], 0, 0),
            post(42, 3, 1, &["astronomia"], 30, 0),
            post(43, 3, 1, &["teatro"], 25, 0),
        ];
        let feed = rank(FeedMode::Mixed, &viewer(), &candidates, &params(), NOW);
        assert_eq!(ids(&feed), [40, 42, 41, 43]);
    }

    #[test]
    fn same_input_gives_same_feed_in_any_order() {
        let mut candidates = vec![
            post(50, 2, 1, &[], 10, 0),
            post(51, 3, 1, &[], 10, 0),
            post(52, 4, 30, &[], 50, 2),
        ];
        let first = rank(
            FeedMode::PublicRanking,
            &viewer(),
            &candidates,
            &params(),
            NOW,
        );
        candidates.reverse();
        let second = rank(
            FeedMode::PublicRanking,
            &viewer(),
            &candidates,
            &params(),
            NOW,
        );

        assert_eq!(ids(&first), [52, 50, 51]);
        assert_eq!(first, second);
    }
}
