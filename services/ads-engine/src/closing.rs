//! Fechamento do mês de um criador: quanto ele recebe, e por quê.
//!
//! A conta de cada criador só usa os dados dele: as views com anúncio dos
//! vídeos dele e os anúncios de shorts em que um short dele estava no bloco.
//! Por isso cada criador consegue refazer o próprio fechamento no verificador,
//! sem ver os dados de mais ninguém.
//!
//! O fechamento também devolve o texto de cada linha do extrato. A rede junta
//! as linhas de todos os criadores numa árvore de Merkle e publica a raiz no
//! registro público; o extrato de cada criador leva as provas de que as linhas
//! dele estão nessa árvore. Os textos são montados aqui, e só aqui, para o
//! backend e o verificador nunca discordarem do formato.

use std::collections::{BTreeMap, HashMap};

use serde::{Deserialize, Serialize};

use crate::{Params, ShortView, effective_views, split_shorts_revenue};

/// Fuso de Brasília, sem horário de verão: o "dia" dos limites do antifraude.
const BRASILIA_OFFSET: i64 = -3 * 3600;

/// Uma view de vídeo em que o anúncio passou.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct VideoAdView {
    /// Pseudônimo de quem viu, diferente a cada mês.
    pub viewer: String,
    pub post: u64,
    pub campaign: u64,
    pub regional: bool,
    /// Quando, em segundos Unix.
    pub at: i64,
    /// Conta verificada pelo gov.br. Conta básica não conta para pagamento:
    /// sem gov.br, nada garante que é uma pessoa.
    pub viewer_verified: bool,
}

/// Um anúncio de shorts em que um short do criador estava no bloco.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ShortsImpression {
    pub id: u64,
    pub revenue_cents: u64,
    pub at: i64,
    /// Todos os shorts do bloco, de todos os criadores, porque o rateio
    /// depende do tempo assistido de cada um.
    pub views: Vec<ShortsBlockView>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ShortsBlockView {
    pub creator: String,
    pub watched_ms: u64,
    pub monetized: bool,
}

/// O mês de um criador, como entra no fechamento.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CreatorMonth {
    /// "2026-10".
    pub month: String,
    pub creator: String,
    /// Saldo que ficou do mês anterior, abaixo do mínimo de repasse.
    #[serde(default)]
    pub carry_in_cents: u64,
    #[serde(default)]
    pub video_views: Vec<VideoAdView>,
    #[serde(default)]
    pub shorts: Vec<ShortsImpression>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ViewStatus {
    Counted,
    /// Conta básica, sem gov.br.
    UnverifiedViewer,
    /// A mesma pessoa já tinha visto este vídeo hoje.
    RepeatedSameDay,
    /// A mesma pessoa passou do limite de views deste criador no dia.
    CreatorDailyLimit,
}

impl ViewStatus {
    pub fn code(self) -> &'static str {
        match self {
            ViewStatus::Counted => "conta",
            ViewStatus::UnverifiedViewer => "conta-basica",
            ViewStatus::RepeatedSameDay => "repetida-no-dia",
            ViewStatus::CreatorDailyLimit => "limite-por-criador",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CreatorResult {
    pub month: String,
    pub creator: String,
    /// Um status por view, na ordem de `video_views` da entrada.
    pub statuses: Vec<ViewStatus>,
    pub national_views: u64,
    pub regional_views: u64,
    pub discarded_views: u64,
    /// Nacionais mais regionais pesadas por `regional_view_percent`.
    pub weighted_views: u64,
    /// Depois das faixas.
    pub effective_views: u64,
    pub video_cents: u64,
    /// Parte do criador em cada anúncio de shorts, na ordem da entrada.
    pub shorts_cents_each: Vec<u64>,
    pub shorts_cents: u64,
    pub carry_in_cents: u64,
    pub total_cents: u64,
    /// Total acima do mínimo: vai por PIX. Senão, fica para o mês seguinte.
    pub payable: bool,
    /// O texto de cada linha do extrato, na ordem: views, shorts e o total.
    pub leaves: Vec<String>,
}

/// Fecha o mês de um criador.
pub fn close(month: &CreatorMonth, params: &Params) -> CreatorResult {
    let statuses = classify(&month.video_views, params);

    let mut national = 0;
    let mut regional = 0;
    for (view, status) in month.video_views.iter().zip(&statuses) {
        if *status == ViewStatus::Counted {
            if view.regional {
                regional += 1;
            } else {
                national += 1;
            }
        }
    }
    let discarded = month.video_views.len() as u64 - national - regional;

    let weighted = national + regional * u64::from(params.payout.regional_view_percent) / 100;
    let effective = effective_views(weighted, &params.payout_bands);
    let video_cents =
        (u128::from(effective) * u128::from(params.payout.base_cents_per_thousand) / 1000) as u64;

    let shorts_cents_each: Vec<u64> = month
        .shorts
        .iter()
        .map(|impression| shorts_share(impression, &month.creator, params))
        .collect();
    let shorts_cents: u64 = shorts_cents_each.iter().sum();

    let total = video_cents + shorts_cents + month.carry_in_cents;

    let mut result = CreatorResult {
        month: month.month.clone(),
        creator: month.creator.clone(),
        statuses,
        national_views: national,
        regional_views: regional,
        discarded_views: discarded,
        weighted_views: weighted,
        effective_views: effective,
        video_cents,
        shorts_cents_each,
        shorts_cents,
        carry_in_cents: month.carry_in_cents,
        total_cents: total,
        payable: total >= params.payout.minimum_payout_cents,
        leaves: Vec::new(),
    };
    result.leaves = leaves(month, &result);
    result
}

/// Quanto vai para os criadores de um anúncio de shorts, antes do rateio.
pub fn shorts_creator_pool(revenue_cents: u64, params: &Params) -> u64 {
    revenue_cents * u64::from(params.payout.creator_share_percent) / 100
}

/// A parte do criador num anúncio de shorts: a parte dos criadores, dividida
/// pelo tempo assistido. Os criadores do bloco viram números (1, 2, ...) na
/// ordem do id, como no rateio feito na hora do anúncio.
pub fn shorts_share(impression: &ShortsImpression, creator: &str, params: &Params) -> u64 {
    let mut creators: Vec<&str> = impression
        .views
        .iter()
        .map(|v| v.creator.as_str())
        .collect();
    creators.sort_unstable();
    creators.dedup();
    let index: HashMap<&str, u64> = creators
        .iter()
        .enumerate()
        .map(|(i, c)| (*c, i as u64 + 1))
        .collect();

    let views: Vec<ShortView> = impression
        .views
        .iter()
        .map(|v| ShortView {
            creator_id: index[v.creator.as_str()],
            watched_ms: v.watched_ms,
            monetized: v.monetized,
        })
        .collect();

    let shares = split_shorts_revenue(
        shorts_creator_pool(impression.revenue_cents, params),
        &views,
    );
    index
        .get(creator)
        .and_then(|id| shares.get(id))
        .copied()
        .unwrap_or(0)
}

/// Aplica as regras do antifraude, view a view, em ordem de tempo.
fn classify(views: &[VideoAdView], params: &Params) -> Vec<ViewStatus> {
    let mut order: Vec<usize> = (0..views.len()).collect();
    order.sort_by(|&a, &b| {
        let (va, vb) = (&views[a], &views[b]);
        (va.at, &va.viewer, va.post, va.campaign).cmp(&(vb.at, &vb.viewer, vb.post, vb.campaign))
    });

    let limits = &params.antifraud;
    let mut per_post: BTreeMap<(&str, u64, i64), u32> = BTreeMap::new();
    let mut per_creator: BTreeMap<(&str, i64), u32> = BTreeMap::new();
    let mut statuses = vec![ViewStatus::Counted; views.len()];

    for i in order {
        let view = &views[i];
        let day = (view.at + BRASILIA_OFFSET).div_euclid(86_400);

        statuses[i] = if !view.viewer_verified {
            ViewStatus::UnverifiedViewer
        } else {
            let post_count = per_post.entry((&view.viewer, view.post, day)).or_default();
            let creator_count = per_creator.entry((&view.viewer, day)).or_default();

            if *post_count >= limits.max_views_per_viewer_post_per_day {
                ViewStatus::RepeatedSameDay
            } else if *creator_count >= limits.max_views_per_viewer_creator_per_day {
                ViewStatus::CreatorDailyLimit
            } else {
                *post_count += 1;
                *creator_count += 1;
                ViewStatus::Counted
            }
        };
    }
    statuses
}

/// Os textos das linhas do extrato. Mudar qualquer formato aqui muda as raízes
/// publicadas: é mudança de regra, com versão nova do motor.
fn leaves(month: &CreatorMonth, result: &CreatorResult) -> Vec<String> {
    let mut lines = Vec::new();

    for (view, status) in month.video_views.iter().zip(&result.statuses) {
        lines.push(format!(
            "anuncio-video|{}|{}|{}|{}|{}|{}|{}|{}",
            month.month,
            month.creator,
            view.viewer,
            view.post,
            view.campaign,
            if view.regional {
                "regional"
            } else {
                "nacional"
            },
            view.at,
            status.code()
        ));
    }

    for (impression, cents) in month.shorts.iter().zip(&result.shorts_cents_each) {
        let block = impression
            .views
            .iter()
            .map(|v| format!("{}:{}:{}", v.creator, v.watched_ms, u8::from(v.monetized)))
            .collect::<Vec<_>>()
            .join(",");
        lines.push(format!(
            "anuncio-shorts|{}|{}|{}|{}|{}|{}|{}",
            month.month,
            month.creator,
            impression.id,
            impression.revenue_cents,
            impression.at,
            block,
            cents
        ));
    }

    lines.push(format!(
        "total|{}|{}|{}|{}|{}|{}|{}|{}|{}|{}",
        month.month,
        month.creator,
        result.national_views,
        result.regional_views,
        result.effective_views,
        result.video_cents,
        result.shorts_cents,
        result.carry_in_cents,
        result.total_cents,
        if result.payable {
            "repasse"
        } else {
            "fica-para-o-proximo-mes"
        }
    ));
    lines
}

#[cfg(test)]
mod tests {
    use super::*;

    fn params() -> Params {
        Params::from_toml_str(include_str!("../../../params/ads.toml")).unwrap()
    }

    // 10/10/2026 às 15h em Brasília.
    const AFTERNOON: i64 = 1_791_655_200;

    fn view(viewer: &str, post: u64, at: i64) -> VideoAdView {
        VideoAdView {
            viewer: viewer.into(),
            post,
            campaign: 1,
            regional: false,
            at,
            viewer_verified: true,
        }
    }

    fn month(views: Vec<VideoAdView>) -> CreatorMonth {
        CreatorMonth {
            month: "2026-10".into(),
            creator: "criadora".into(),
            carry_in_cents: 0,
            video_views: views,
            shorts: vec![],
        }
    }

    #[test]
    fn the_same_person_counts_once_per_video_per_day() {
        let result = close(
            &month(vec![
                view("a", 1, AFTERNOON),
                view("a", 1, AFTERNOON + 60),
                // No dia seguinte, conta de novo.
                view("a", 1, AFTERNOON + 86_400),
                view("b", 1, AFTERNOON + 120),
            ]),
            &params(),
        );
        assert_eq!(
            result.statuses,
            vec![
                ViewStatus::Counted,
                ViewStatus::RepeatedSameDay,
                ViewStatus::Counted,
                ViewStatus::Counted
            ]
        );
        assert_eq!((result.national_views, result.discarded_views), (3, 1));
    }

    #[test]
    fn the_day_turns_at_midnight_in_brasilia() {
        // 23h59 e 0h01 de Brasília são dias diferentes, mesmo sendo o mesmo dia em UTC.
        let midnight = 1_791_687_600; // 11/10/2026 0h em Brasília
        let result = close(
            &month(vec![
                view("a", 1, midnight - 60),
                view("a", 1, midnight + 60),
            ]),
            &params(),
        );
        assert_eq!(result.national_views, 2);
    }

    #[test]
    fn one_person_cannot_inflate_one_creator() {
        let views = (0..15)
            .map(|post| view("a", post, AFTERNOON + post as i64))
            .collect();
        let result = close(&month(views), &params());
        assert_eq!(result.national_views, 10);
        assert_eq!(result.statuses[10], ViewStatus::CreatorDailyLimit);
    }

    #[test]
    fn basic_accounts_do_not_count() {
        let mut unverified = view("bot", 1, AFTERNOON);
        unverified.viewer_verified = false;
        let result = close(&month(vec![unverified]), &params());
        assert_eq!(result.statuses, vec![ViewStatus::UnverifiedViewer]);
        assert_eq!(result.total_cents, 0);
    }

    #[test]
    fn regional_views_weigh_less_and_bands_apply() {
        let mut views: Vec<VideoAdView> = (0..1000)
            .map(|i| view(&format!("n{i}"), 1, AFTERNOON))
            .collect();
        views.extend((0..1000).map(|i| VideoAdView {
            regional: true,
            ..view(&format!("r{i}"), 1, AFTERNOON)
        }));
        let result = close(&month(views), &params());

        assert_eq!(result.weighted_views, 1500);
        // R$ 11,00 por mil na primeira faixa: 1.500 views valem R$ 16,50.
        assert_eq!(result.video_cents, 1650);
        assert!(result.payable);
    }

    #[test]
    fn shorts_pay_the_creator_share_by_watch_time() {
        let impression = ShortsImpression {
            id: 7,
            revenue_cents: 1000,
            at: AFTERNOON,
            views: vec![
                ShortsBlockView {
                    creator: "criadora".into(),
                    watched_ms: 30_000,
                    monetized: true,
                },
                ShortsBlockView {
                    creator: "outro".into(),
                    watched_ms: 10_000,
                    monetized: true,
                },
            ],
        };
        let mut input = month(vec![]);
        input.shorts = vec![impression];
        let result = close(&input, &params());

        // 55% de R$ 10,00 para os criadores, três quartos para quem teve três
        // quartos do tempo. O centavo que sobra vai para o menor id.
        assert_eq!(result.shorts_cents, 413);
    }

    #[test]
    fn small_totals_wait_for_next_month_and_add_up() {
        let mut input = month(vec![view("a", 1, AFTERNOON)]);
        let first = close(&input, &params());
        assert!(!first.payable);

        input.carry_in_cents = 98;
        let second = close(&input, &params());
        assert_eq!(second.total_cents, 99);
        assert!(!second.payable);

        input.carry_in_cents = 99;
        assert!(close(&input, &params()).payable);
    }

    #[test]
    fn leaves_commit_to_every_line_and_the_total() {
        let result = close(&month(vec![view("a", 1, AFTERNOON)]), &params());
        assert_eq!(
            result.leaves,
            vec![
                format!("anuncio-video|2026-10|criadora|a|1|1|nacional|{AFTERNOON}|conta"),
                "total|2026-10|criadora|1|0|1|1|0|0|1|fica-para-o-proximo-mes".to_string(),
            ]
        );
    }
}
