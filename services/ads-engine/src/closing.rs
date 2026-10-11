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

use crate::{BandDifference, Params, ShortView, effective_views, split_shorts_revenue};

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
    /// Conta verificada pelo gov.br. Com conta básica, a parte dos criadores
    /// fica com o fundo, como nas views dos vídeos.
    pub viewer_verified: bool,
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
    /// A parte do bônus dos criadores pequenos.
    #[serde(default)]
    pub bonus_cents: u64,
    pub carry_in_cents: u64,
    pub total_cents: u64,
    /// Total acima do mínimo: vai por PIX. Senão, fica para o mês seguinte.
    pub payable: bool,
    /// O texto de cada linha do extrato, na ordem: views, shorts e o total.
    pub leaves: Vec<String>,
}

/// O bônus dos criadores pequenos num mês: o que as faixas deixaram de
/// pagar a quem cresceu, e a soma das views de quem ficou na primeira faixa.
/// Os dois números vão para o registro público; com eles, cada criador refaz
/// a própria parte sem ver os dados de mais ninguém.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Bonus {
    pub pool_cents: u64,
    pub eligible_views: u64,
}

/// Fecha o mês de todos os criadores: primeiro cada um sem bônus, para
/// somar o bônus, e depois cada um com a sua parte.
pub fn close_all(months: &[CreatorMonth], params: &Params) -> (Vec<CreatorResult>, Bonus) {
    let base: Vec<CreatorResult> = months
        .iter()
        .map(|month| close(month, params, Bonus::default()))
        .collect();

    let bonus = match params.payout.band_difference {
        BandDifference::Fundo => Bonus::default(),
        BandDifference::BonusPequenos => Bonus {
            pool_cents: base.iter().map(|r| band_difference_cents(r, params)).sum(),
            eligible_views: base
                .iter()
                .filter(|r| eligible(r, params))
                .map(|r| r.weighted_views)
                .sum(),
        },
    };

    let results = months
        .iter()
        .map(|month| close(month, params, bonus))
        .collect();
    (results, bonus)
}

/// O que as faixas deixaram de pagar a este criador: o valor base de todas
/// as views dele menos o que ele recebeu nos vídeos.
fn band_difference_cents(result: &CreatorResult, params: &Params) -> u64 {
    let full = u128::from(result.weighted_views)
        * u128::from(params.payout.base_cents_per_thousand)
        / 1000;
    (full as u64).saturating_sub(result.video_cents)
}

/// Criador pequeno: teve views com anúncio no mês e todas couberam na
/// primeira faixa.
fn eligible(result: &CreatorResult, params: &Params) -> bool {
    let first = params
        .payout_bands
        .first()
        .and_then(|band| band.up_to)
        .unwrap_or(u64::MAX);
    result.weighted_views > 0 && result.weighted_views <= first
}

/// Fecha o mês de um criador, com o bônus do mês (`Bonus::default()` sem
/// bônus).
pub fn close(month: &CreatorMonth, params: &Params, bonus: Bonus) -> CreatorResult {
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
        bonus_cents: 0,
        carry_in_cents: month.carry_in_cents,
        total_cents: 0,
        payable: false,
        leaves: Vec::new(),
    };

    // A parte do bônus é proporcional às views; o centavo que sobra da
    // divisão fica com o fundo.
    if eligible(&result, params) && bonus.eligible_views > 0 {
        result.bonus_cents = (u128::from(bonus.pool_cents) * u128::from(result.weighted_views)
            / u128::from(bonus.eligible_views)) as u64;
    }
    result.total_cents =
        result.video_cents + result.shorts_cents + result.bonus_cents + month.carry_in_cents;
    result.payable = result.total_cents >= params.payout.minimum_payout_cents;
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
    if !impression.viewer_verified {
        return 0;
    }
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
        params.payout.shorts_split,
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
            "anuncio-shorts|{}|{}|{}|{}|{}|{}|{}|{}",
            month.month,
            month.creator,
            impression.id,
            impression.revenue_cents,
            impression.at,
            if impression.viewer_verified {
                "verificada"
            } else {
                "conta-basica"
            },
            block,
            cents
        ));
    }

    lines.push(format!(
        "total|{}|{}|{}|{}|{}|{}|{}|{}|{}|{}|{}",
        month.month,
        month.creator,
        result.national_views,
        result.regional_views,
        result.effective_views,
        result.video_cents,
        result.shorts_cents,
        result.bonus_cents,
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

    fn close_one(month: &CreatorMonth, params: &Params) -> CreatorResult {
        close(month, params, Bonus::default())
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
        let result = close_one(
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
        let result = close_one(
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
        let result = close_one(&month(views), &params());
        assert_eq!(result.national_views, 10);
        assert_eq!(result.statuses[10], ViewStatus::CreatorDailyLimit);
    }

    #[test]
    fn basic_accounts_do_not_count() {
        let mut unverified = view("bot", 1, AFTERNOON);
        unverified.viewer_verified = false;
        let result = close_one(&month(vec![unverified]), &params());
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
        let result = close_one(&month(views), &params());

        assert_eq!(result.weighted_views, 1500);
        // R$ 11,00 por mil na primeira faixa: 1.500 views valem R$ 16,50.
        assert_eq!(result.video_cents, 1650);
        assert!(result.payable);
    }

    #[test]
    fn shorts_pay_the_creator_share_in_equal_parts() {
        let impression = ShortsImpression {
            id: 7,
            revenue_cents: 1000,
            at: AFTERNOON,
            viewer_verified: true,
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
        input.shorts = vec![impression.clone()];
        let result = close_one(&input, &params());

        // 55% de R$ 10,00 para os criadores, em partes iguais por short
        // (params/ads.toml): dois shorts, metade para cada um, seja qual for
        // o tempo assistido.
        assert_eq!(result.shorts_cents, 275);

        // Com conta básica, a parte dos criadores fica com o fundo, e a linha
        // do extrato diz por quê.
        input.shorts = vec![ShortsImpression {
            viewer_verified: false,
            ..impression
        }];
        let basic = close_one(&input, &params());
        assert_eq!(basic.shorts_cents, 0);
        assert!(basic.leaves[0].contains("|conta-basica|"));
    }

    #[test]
    fn small_totals_wait_for_next_month_and_add_up() {
        let mut input = month(vec![view("a", 1, AFTERNOON)]);
        let first = close_one(&input, &params());
        assert!(!first.payable);

        input.carry_in_cents = 98;
        let second = close_one(&input, &params());
        assert_eq!(second.total_cents, 99);
        assert!(!second.payable);

        input.carry_in_cents = 99;
        assert!(close_one(&input, &params()).payable);
    }

    #[test]
    fn leaves_commit_to_every_line_and_the_total() {
        let result = close_one(&month(vec![view("a", 1, AFTERNOON)]), &params());
        assert_eq!(
            result.leaves,
            vec![
                format!("anuncio-video|2026-10|criadora|a|1|1|nacional|{AFTERNOON}|conta"),
                "total|2026-10|criadora|1|0|1|1|0|0|0|1|fica-para-o-proximo-mes".to_string(),
            ]
        );
    }

    #[test]
    fn what_the_bands_hold_back_goes_to_small_creators() {
        // Faixas pequenas e R$ 1,00 por view, para a conta caber no teste.
        let source = include_str!("../../../params/ads.toml")
            .replace(
                "base_cents_per_thousand = 1100",
                "base_cents_per_thousand = 100000",
            )
            .replace("up_to = 100_000", "up_to = 2")
            .replace("up_to = 1_000_000", "up_to = 5")
            .replace("up_to = 10_000_000", "up_to = 10");
        let params = Params::from_toml_str(&source).unwrap();

        let creator = |name: &str, viewers: &[&str]| CreatorMonth {
            creator: name.into(),
            ..month(viewers.iter().map(|v| view(v, 1, AFTERNOON)).collect())
        };
        // A grande passou da primeira faixa: 4 views valem 3 (2 a 100% e 2 a
        // 75%), e R$ 1,00 fica para trás. As pequenas dividem pelas views.
        let months = [
            creator("grande", &["a", "b", "c", "d"]),
            creator("pequena-1", &["a"]),
            creator("pequena-2", &["a", "b"]),
        ];
        let (results, bonus) = close_all(&months, &params);

        assert_eq!(
            bonus,
            Bonus {
                pool_cents: 100,
                eligible_views: 3
            }
        );
        let bonuses: Vec<u64> = results.iter().map(|r| r.bonus_cents).collect();
        assert_eq!(bonuses, vec![0, 33, 66]);
        assert_eq!(results[1].total_cents, 100 + 33);

        // Cada uma refaz a própria parte só com os números publicados.
        assert_eq!(close(&months[2], &params, bonus), results[2]);

        let fund_params = Params::from_toml_str(&source.replace(
            "band_difference = \"bonus-pequenos\"",
            "band_difference = \"fundo\"",
        ))
        .unwrap();
        let (_, nothing) = close_all(&months, &fund_params);
        assert_eq!(nothing, Bonus::default());
    }
}
