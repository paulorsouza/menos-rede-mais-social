//! Motor de feed da -rede+social.
//!
//! O feed é um grafo de pessoas e posts. Uma pessoa se liga a um post quando
//! curte ou assiste, e a outra pessoa quando segue. Não existe categoria, tema
//! nem tag: a rede nunca decide do que um post fala, só olha o que as pessoas
//! fazem. Quem curte o que você curte vira seu vizinho, e o que seus vizinhos
//! curtem é o que a bolha sugere.
//!
//! Todos os modos são determinísticos: com os mesmos dados de entrada, os mesmos
//! parâmetros (`params/feed.toml`) e a mesma versão do código, o resultado é
//! sempre o mesmo. É isso que permite a qualquer pessoa refazer o cálculo do
//! feed de alguém e conferir que a rede seguiu as regras publicadas.
//!
//! As contas usam só inteiros, para o resultado não variar de uma máquina para
//! outra.

mod params;

use std::collections::BTreeMap;
use std::collections::BTreeSet;

use serde::{Deserialize, Serialize};

pub use params::Params;

pub type PostId = u64;
pub type UserId = u64;

/// Pontuação de recência de um post recém-publicado.
const RECENCY_MAX: i64 = 1024;

const DAY: i64 = 86_400;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FeedMode {
    /// Na bolha: quem você segue e o que pessoas de gosto parecido curtem.
    Bubble,
    /// Furando a bolha: o que ninguém perto de você curtiu ou assistiu.
    OutsideBubble,
    /// Meio a meio: os dois modos acima, intercalados.
    Mixed,
    /// Sem algoritmo: só quem você segue, do mais novo para o mais antigo.
    Chronological,
    /// Em alta: uma fórmula pública, igual para todo mundo.
    PublicRanking,
}

/// Um post que pode entrar no feed.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Candidate {
    pub post_id: PostId,
    pub author_id: UserId,
    /// Segundos desde 1970 (horário Unix).
    pub created_at: i64,
    pub likes: u32,
    pub saves: u32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EdgeKind {
    Like,
    Watch,
}

/// Uma ligação no grafo: alguém curtiu ou assistiu a um post.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Edge {
    pub user_id: UserId,
    pub post_id: PostId,
    pub kind: EdgeKind,
    /// Quando aconteceu, em segundos Unix.
    pub at: i64,
    /// Só para `watch`: quanto a pessoa assistiu, em milissegundos.
    #[serde(default)]
    pub watched_ms: u64,
}

/// Quem está vendo o feed.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Viewer {
    #[serde(default)]
    pub id: UserId,
    pub follows: BTreeSet<UserId>,
}

/// Por que um post apareceu no feed. Vai junto com cada item até a tela.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "value", rename_all = "snake_case")]
pub enum Reason {
    YouFollow,
    /// Quantas pessoas que você segue curtiram ou assistiram.
    FollowsEngaged(u32),
    /// Quantas pessoas de gosto parecido com o seu curtiram ou assistiram.
    SimilarEngaged(u32),
    /// Ninguém perto de você curtiu ou assistiu.
    OutsideBubble,
    PublicRanking,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RankedItem {
    pub post_id: PostId,
    pub score: i64,
    pub reasons: Vec<Reason>,
}

pub fn rank(
    mode: FeedMode,
    viewer: &Viewer,
    candidates: &[Candidate],
    edges: &[Edge],
    params: &Params,
    now: i64,
) -> Vec<RankedItem> {
    let graph = Graph::build(edges, params, now);
    let neighbors = neighbors(viewer, &graph, params);
    let feed = Feed {
        viewer,
        graph: &graph,
        neighbors: &neighbors,
        params,
        now,
    };

    match mode {
        FeedMode::Bubble => feed.bubble(candidates),
        FeedMode::OutsideBubble => feed.outside_bubble(candidates),
        FeedMode::Mixed => feed.mixed(candidates),
        FeedMode::Chronological => chronological(viewer, candidates),
        FeedMode::PublicRanking => public_ranking(candidates, params, now),
    }
}

/// Quem se ligou a qual post, e com que força. Só entra o que vale pelas
/// regras de `[graph]`: dentro da janela e, no caso de vídeo, assistido de
/// verdade.
#[derive(Debug, Default)]
struct Graph {
    by_user: BTreeMap<UserId, BTreeMap<PostId, u32>>,
    by_post: BTreeMap<PostId, BTreeMap<UserId, u32>>,
}

impl Graph {
    fn build(edges: &[Edge], params: &Params, now: i64) -> Self {
        let rules = &params.graph;
        let window = i64::from(rules.window_days) * DAY;
        let min_watch_ms = u64::from(rules.watch_min_seconds) * 1000;

        // Cada pessoa se liga a cada post no máximo uma vez por tipo, mesmo
        // que tenha assistido várias vezes.
        let mut links: BTreeMap<(UserId, PostId), (bool, bool)> = BTreeMap::new();
        for edge in edges.iter().filter(|edge| now - edge.at <= window) {
            let (liked, watched) = links.entry((edge.user_id, edge.post_id)).or_default();
            match edge.kind {
                EdgeKind::Like => *liked = true,
                EdgeKind::Watch => *watched |= edge.watched_ms >= min_watch_ms,
            }
        }

        let mut graph = Graph::default();
        for ((user, post), (liked, watched)) in links {
            let strength =
                u32::from(liked) * rules.like_weight + u32::from(watched) * rules.watch_weight;
            if strength > 0 {
                graph
                    .by_user
                    .entry(user)
                    .or_default()
                    .insert(post, strength);
                graph
                    .by_post
                    .entry(post)
                    .or_default()
                    .insert(user, strength);
            }
        }
        graph
    }

    fn posts_of(&self, user: UserId) -> impl Iterator<Item = (&PostId, &u32)> {
        self.by_user.get(&user).into_iter().flatten()
    }

    fn people_on(&self, post: PostId) -> impl Iterator<Item = (&UserId, &u32)> {
        self.by_post.get(&post).into_iter().flatten()
    }

    fn touched(&self, user: UserId, post: PostId) -> bool {
        self.by_user
            .get(&user)
            .is_some_and(|posts| posts.contains_key(&post))
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct Neighbor {
    weight: u32,
    followed: bool,
}

/// Pessoas de gosto parecido com o de quem vê o feed, mais quem ela segue.
fn neighbors(viewer: &Viewer, graph: &Graph, params: &Params) -> BTreeMap<UserId, Neighbor> {
    let rules = &params.neighbors;

    // Quantos posts cada pessoa tem em comum com quem vê o feed.
    let mut shared: BTreeMap<UserId, u32> = BTreeMap::new();
    for (post, _) in graph.posts_of(viewer.id) {
        for (user, _) in graph.people_on(*post) {
            if *user != viewer.id {
                *shared.entry(*user).or_default() += 1;
            }
        }
    }

    let mut similar: Vec<(UserId, u32, usize)> = shared
        .into_iter()
        .filter_map(|(user, count)| {
            let total = graph.posts_of(user).count();
            let overlap = u64::from(count) * 100;
            let needed = u64::from(rules.min_overlap_percent) * total as u64;
            (count >= rules.min_shared && overlap >= needed).then_some((user, count, total))
        })
        .collect();
    // Mais posts em comum primeiro. No empate, quem curte menos coisas, porque
    // o gosto dela diz mais.
    similar.sort_by(|a, b| b.1.cmp(&a.1).then(a.2.cmp(&b.2)).then(a.0.cmp(&b.0)));
    similar.truncate(rules.max_neighbors);

    let mut neighbors: BTreeMap<UserId, Neighbor> = similar
        .into_iter()
        .map(|(user, count, _)| {
            let neighbor = Neighbor {
                weight: count,
                followed: false,
            };
            (user, neighbor)
        })
        .collect();

    for user in viewer.follows.iter().filter(|user| **user != viewer.id) {
        let neighbor = neighbors.entry(*user).or_insert(Neighbor {
            weight: 0,
            followed: false,
        });
        neighbor.weight += rules.follow_weight;
        neighbor.followed = true;
    }
    neighbors
}

struct Feed<'a> {
    viewer: &'a Viewer,
    graph: &'a Graph,
    neighbors: &'a BTreeMap<UserId, Neighbor>,
    params: &'a Params,
    now: i64,
}

impl Feed<'_> {
    fn recency(&self, candidate: &Candidate) -> i64 {
        recency(candidate.created_at, self.now, self.params)
    }

    fn is_near(&self, user: UserId) -> bool {
        user == self.viewer.id || self.neighbors.contains_key(&user)
    }

    /// Posts de quem você segue e o que seus vizinhos curtiram ou assistiram.
    /// O que você mesmo já curtiu ou assistiu não volta como sugestão.
    fn bubble(&self, candidates: &[Candidate]) -> Vec<RankedItem> {
        let rules = &self.params.bubble;

        let mut items: Vec<RankedItem> = candidates
            .iter()
            .filter(|candidate| candidate.author_id != self.viewer.id)
            .filter_map(|candidate| {
                let follows_author = self.viewer.follows.contains(&candidate.author_id);
                if !follows_author && self.graph.touched(self.viewer.id, candidate.post_id) {
                    return None;
                }

                let mut points = 0;
                let (mut by_follows, mut by_similar) = (0, 0);
                for (user, strength) in self.graph.people_on(candidate.post_id) {
                    if let Some(neighbor) = self.neighbors.get(user) {
                        points += i64::from(neighbor.weight) * i64::from(*strength);
                        if neighbor.followed {
                            by_follows += 1;
                        } else {
                            by_similar += 1;
                        }
                    }
                }

                let mut reasons = Vec::new();
                if follows_author {
                    points += rules.author_points;
                    reasons.push(Reason::YouFollow);
                }
                if by_follows > 0 {
                    reasons.push(Reason::FollowsEngaged(by_follows));
                }
                if by_similar > 0 {
                    reasons.push(Reason::SimilarEngaged(by_similar));
                }
                if reasons.is_empty() {
                    return None;
                }

                points += rules.engagement_weight * engagement(candidate);
                Some(RankedItem {
                    post_id: candidate.post_id,
                    score: points * self.recency(candidate),
                    reasons,
                })
            })
            .collect();

        sort_by_score(&mut items);
        items
    }

    /// Só o que é totalmente diferente: posts que nem você, nem quem você
    /// segue, nem seus vizinhos curtiram ou assistiram, de autores que também
    /// não estão perto de você.
    ///
    /// Para ninguém ocupar o feed sozinho, os autores se revezam: primeiro o
    /// melhor post de cada um, depois o segundo de cada um, e assim por diante.
    fn outside_bubble(&self, candidates: &[Candidate]) -> Vec<RankedItem> {
        let min_engagement = i64::from(self.params.outside_bubble.min_engagement);
        let mut by_author: BTreeMap<UserId, Vec<RankedItem>> = BTreeMap::new();

        for candidate in candidates.iter().filter(|candidate| {
            !self.is_near(candidate.author_id)
                && engagement(candidate) >= min_engagement
                && !self
                    .graph
                    .people_on(candidate.post_id)
                    .any(|(user, _)| self.is_near(*user))
        }) {
            by_author
                .entry(candidate.author_id)
                .or_default()
                .push(RankedItem {
                    post_id: candidate.post_id,
                    score: engagement(candidate) * self.recency(candidate),
                    reasons: vec![Reason::OutsideBubble],
                });
        }

        let mut turns: Vec<(usize, RankedItem)> = Vec::new();
        for items in by_author.values_mut() {
            sort_by_score(items);
            turns.extend(items.drain(..).enumerate());
        }
        turns.sort_by(|(turn_a, a), (turn_b, b)| {
            turn_a
                .cmp(turn_b)
                .then(b.score.cmp(&a.score))
                .then(a.post_id.cmp(&b.post_id))
        });
        turns.into_iter().map(|(_, item)| item).collect()
    }

    /// Intercala os dois modos: a cada `outside_every` posições, uma vem de
    /// fora da bolha. Quando um dos lados acaba, o outro completa o feed.
    fn mixed(&self, candidates: &[Candidate]) -> Vec<RankedItem> {
        let every = self.params.mixed.outside_every.max(1);
        let mut inside = self.bubble(candidates).into_iter();
        let mut outside = self.outside_bubble(candidates).into_iter();

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
    const ME: UserId = 99;

    fn params() -> Params {
        Params::from_toml_str(include_str!("../../../params/feed.toml"))
            .expect("params/feed.toml precisa ser válido")
    }

    fn post(post_id: PostId, author_id: UserId, hours_ago: i64, likes: u32) -> Candidate {
        Candidate {
            post_id,
            author_id,
            created_at: NOW - hours_ago * HOUR,
            likes,
            saves: 0,
        }
    }

    fn like(user_id: UserId, post_id: PostId, days_ago: i64) -> Edge {
        Edge {
            user_id,
            post_id,
            kind: EdgeKind::Like,
            at: NOW - days_ago * DAY,
            watched_ms: 0,
        }
    }

    fn watch(user_id: UserId, post_id: PostId, seconds: u64) -> Edge {
        Edge {
            user_id,
            post_id,
            kind: EdgeKind::Watch,
            at: NOW - DAY,
            watched_ms: seconds * 1000,
        }
    }

    /// Eu (99) sigo a pessoa 1.
    fn viewer() -> Viewer {
        Viewer {
            id: ME,
            follows: BTreeSet::from([1]),
        }
    }

    /// Curti os posts 100 e 101 e assisti ao 102. Do 103 eu passei direto.
    ///
    /// - A pessoa 5 curtiu os mesmos 100 e 101, e quase nada além: é vizinha.
    /// - A 6 também curtiu 100 e 101, mas curte tudo: não é vizinha.
    /// - A 7 tem só um post em comum comigo: ainda não é vizinha.
    /// - A 1 eu sigo. A 8 está longe de tudo.
    fn edges() -> Vec<Edge> {
        let mut edges = vec![
            like(ME, 100, 1),
            like(ME, 101, 2),
            watch(ME, 102, 30),
            watch(ME, 103, 3),
            like(5, 100, 1),
            like(5, 101, 1),
            like(5, 200, 1),
            like(6, 100, 1),
            like(6, 101, 1),
            like(6, 201, 1),
            like(7, 100, 1),
            like(7, 202, 1),
            like(1, 203, 1),
            like(8, 204, 1),
            // Fora da janela de 90 dias: não liga mais ninguém a nada.
            like(5, 205, 120),
        ];
        edges.extend((300..330).map(|post| like(6, post, 1)));
        edges
    }

    fn candidates() -> Vec<Candidate> {
        vec![
            post(100, 3, 1, 50),
            post(200, 3, 1, 0),
            post(201, 3, 1, 20),
            post(202, 3, 1, 15),
            post(203, 4, 1, 0),
            post(204, 1, 1, 0),
            post(205, 4, 1, 30),
            post(206, ME, 1, 90),
        ]
    }

    fn feed(mode: FeedMode) -> Vec<RankedItem> {
        rank(mode, &viewer(), &candidates(), &edges(), &params(), NOW)
    }

    fn ids(items: &[RankedItem]) -> Vec<PostId> {
        items.iter().map(|item| item.post_id).collect()
    }

    #[test]
    fn public_params_file_is_valid() {
        assert_eq!(params().version, 2);
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
    fn watching_counts_only_when_the_person_really_watched() {
        let graph = Graph::build(&edges(), &params(), NOW);
        let mine: Vec<&PostId> = graph.posts_of(ME).map(|(post, _)| post).collect();
        assert_eq!(mine, [&100, &101, &102]);
    }

    #[test]
    fn neighbors_are_people_with_similar_taste_plus_follows() {
        let graph = Graph::build(&edges(), &params(), NOW);
        let neighbors = neighbors(&viewer(), &graph, &params());

        assert_eq!(
            neighbors,
            BTreeMap::from([
                (
                    1,
                    Neighbor {
                        weight: 3,
                        followed: true
                    }
                ),
                (
                    5,
                    Neighbor {
                        weight: 2,
                        followed: false
                    }
                ),
            ])
        );
    }

    #[test]
    fn bubble_suggests_what_follows_and_neighbors_liked() {
        let feed = feed(FeedMode::Bubble);

        assert_eq!(ids(&feed), [204, 203, 200]);
        assert_eq!(feed[0].reasons, [Reason::YouFollow]);
        assert_eq!(feed[1].reasons, [Reason::FollowsEngaged(1)]);
        assert_eq!(feed[2].reasons, [Reason::SimilarEngaged(1)]);
    }

    #[test]
    fn outside_bubble_shows_what_nobody_near_you_touched_one_author_at_a_time() {
        let feed = feed(FeedMode::OutsideBubble);

        // O autor 3 tem dois posts longe de mim, mas o autor 4 entra antes do
        // segundo dele.
        assert_eq!(ids(&feed), [205, 201, 202]);
        assert_eq!(feed[0].reasons, [Reason::OutsideBubble]);
    }

    #[test]
    fn mixed_alternates_inside_and_outside() {
        assert_eq!(ids(&feed(FeedMode::Mixed)), [204, 205, 203, 201, 200, 202]);
    }

    #[test]
    fn chronological_shows_only_follows_newest_first() {
        let candidates = [post(10, 1, 5, 0), post(11, 2, 1, 50), post(12, 1, 1, 0)];
        let feed = rank(
            FeedMode::Chronological,
            &viewer(),
            &candidates,
            &[],
            &params(),
            NOW,
        );
        assert_eq!(ids(&feed), [12, 10]);
    }

    #[test]
    fn same_input_gives_same_feed_in_any_order() {
        let mut candidates = vec![post(60, 2, 1, 10), post(61, 3, 1, 10), post(62, 4, 30, 50)];
        candidates[2].saves = 2;
        let mut edges = edges();

        let first = rank(
            FeedMode::PublicRanking,
            &viewer(),
            &candidates,
            &edges,
            &params(),
            NOW,
        );
        candidates.reverse();
        edges.reverse();
        let second = rank(
            FeedMode::PublicRanking,
            &viewer(),
            &candidates,
            &edges,
            &params(),
            NOW,
        );
        assert_eq!(ids(&first), [62, 60, 61]);
        assert_eq!(first, second);

        let mut shuffled = edges.clone();
        shuffled.rotate_left(5);
        assert_eq!(
            rank(
                FeedMode::Mixed,
                &viewer(),
                &self::candidates(),
                &edges,
                &params(),
                NOW
            ),
            rank(
                FeedMode::Mixed,
                &viewer(),
                &self::candidates(),
                &shuffled,
                &params(),
                NOW
            ),
        );
    }
}
