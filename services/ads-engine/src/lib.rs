//! Motor de anúncios da -rede+social: quanto cada criador recebe.
//!
//! Dinheiro é sempre contado em centavos inteiros. Quando uma divisão não é
//! exata, os centavos que sobram vão para quem tinha a maior fração, e o empate
//! é decidido pelo id do criador. Nenhum centavo some no arredondamento.

mod params;

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};

pub use params::{Params, ParamsError, PayoutBand};

pub type UserId = u64;

/// Quantas exibições cabem nas horas de anúncio compradas para um dia.
pub fn impressions_per_day(hours_per_day: u64, ad_seconds: u64) -> u64 {
    assert!(
        ad_seconds > 0,
        "a duração do anúncio precisa ser maior que zero"
    );
    hours_per_day * 3600 / ad_seconds
}

/// Quantas views o criador recebe pelo valor cheio depois de aplicar as faixas.
///
/// Cada faixa vale só para as views dentro dela, como no imposto de renda.
/// Por isso o total nunca diminui quando o criador cresce.
pub fn effective_views(views: u64, bands: &[PayoutBand]) -> u64 {
    let mut weighted: u128 = 0;
    let mut floor = 0;

    for band in bands {
        if views <= floor {
            break;
        }
        let ceiling = band.up_to.unwrap_or(u64::MAX).min(views);
        weighted += u128::from(ceiling - floor) * u128::from(band.percent);
        floor = ceiling;
    }

    (weighted / 100) as u64
}

/// Pagamento do mês, em centavos. `cents_per_thousand` é o valor base pago por
/// mil views na primeira faixa.
pub fn monthly_payout_cents(views: u64, cents_per_thousand: u64, bands: &[PayoutBand]) -> u64 {
    let effective = u128::from(effective_views(views, bands));
    (effective * u128::from(cents_per_thousand) / 1000) as u64
}

/// Um short assistido antes de um anúncio.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ShortView {
    pub creator_id: UserId,
    pub watched_ms: u64,
    /// Falso quando o criador desligou os anúncios.
    pub monetized: bool,
}

/// Divide a receita de um anúncio de shorts entre os criadores dos shorts
/// assistidos antes dele, proporcional ao tempo assistido de cada um.
///
/// Quem desligou os anúncios fica de fora. Se ninguém tiver anúncio ligado, o
/// mapa volta vazio e a receita fica com o fundo de infraestrutura.
pub fn split_shorts_revenue(revenue_cents: u64, views: &[ShortView]) -> BTreeMap<UserId, u64> {
    let mut watched: BTreeMap<UserId, u64> = BTreeMap::new();
    for view in views
        .iter()
        .filter(|view| view.monetized && view.watched_ms > 0)
    {
        *watched.entry(view.creator_id).or_default() += view.watched_ms;
    }

    let total: u128 = watched.values().map(|&ms| u128::from(ms)).sum();
    if total == 0 {
        return BTreeMap::new();
    }

    let revenue = u128::from(revenue_cents);
    let mut shares = BTreeMap::new();
    let mut remainders = Vec::with_capacity(watched.len());
    let mut distributed = 0;

    for (&creator_id, &ms) in &watched {
        let exact = revenue * u128::from(ms);
        let share = exact / total;
        shares.insert(creator_id, share as u64);
        remainders.push((exact % total, creator_id));
        distributed += share;
    }

    remainders.sort_by(|a, b| b.0.cmp(&a.0).then(a.1.cmp(&b.1)));
    let leftover = (revenue - distributed) as usize;
    for (_, creator_id) in remainders.into_iter().take(leftover) {
        *shares.entry(creator_id).or_default() += 1;
    }

    shares
}

#[cfg(test)]
mod tests {
    use super::*;

    fn params() -> Params {
        Params::from_toml_str(include_str!("../../../params/ads.toml"))
            .expect("params/ads.toml precisa ser válido")
    }

    fn view(creator_id: UserId, seconds: u64, monetized: bool) -> ShortView {
        ShortView {
            creator_id,
            watched_ms: seconds * 1000,
            monetized,
        }
    }

    #[test]
    fn public_params_file_is_valid() {
        let params = params();
        assert_eq!(params.shorts_ad_every, 6);
        assert_eq!(params.payout_bands.len(), 4);
    }

    #[test]
    fn hours_become_impressions() {
        // Exemplo do plano: 10.000 horas por dia de um anúncio de 30 segundos.
        assert_eq!(impressions_per_day(10_000, 30), 1_200_000);
    }

    #[test]
    fn effective_views_match_plan_example() {
        let bands = params().payout_bands;
        assert_eq!(effective_views(50_000, &bands), 50_000);
        assert_eq!(effective_views(2_000_000, &bands), 1_275_000);
    }

    #[test]
    fn growing_never_pays_less() {
        let bands = params().payout_bands;
        let samples = [
            0, 1, 99_999, 100_000, 100_001, 999_999, 1_000_000, 1_000_001, 9_999_999, 10_000_000,
            10_000_001, 50_000_000,
        ];
        for pair in samples.windows(2) {
            assert!(effective_views(pair[1], &bands) >= effective_views(pair[0], &bands));
        }
    }

    #[test]
    fn monthly_payout_in_cents() {
        // Valor base ilustrativo: R$ 2,00 por mil views.
        let bands = params().payout_bands;
        assert_eq!(monthly_payout_cents(2_000_000, 200, &bands), 255_000);
    }

    #[test]
    fn shorts_revenue_follows_watch_time() {
        let views = [
            view(1, 30, true),
            view(2, 30, true),
            view(3, 60, false),
            view(1, 40, true),
        ];
        let shares = split_shorts_revenue(1_000, &views);
        assert_eq!(shares, BTreeMap::from([(1, 700), (2, 300)]));
    }

    #[test]
    fn no_cent_is_lost_when_split_is_inexact() {
        let views = [view(3, 10, true), view(1, 10, true), view(2, 10, true)];
        let shares = split_shorts_revenue(100, &views);
        assert_eq!(shares, BTreeMap::from([(1, 34), (2, 33), (3, 33)]));
        assert_eq!(shares.values().sum::<u64>(), 100);
    }

    #[test]
    fn revenue_stays_with_fund_when_nobody_monetizes() {
        let views = [view(1, 30, false), view(2, 30, false)];
        assert!(split_shorts_revenue(1_000, &views).is_empty());
    }

    #[test]
    fn rising_percent_is_rejected() {
        let source = "version = 1\nshorts_ad_every = 6\n\
            [[payout_bands]]\nup_to = 100\npercent = 50\n\
            [[payout_bands]]\npercent = 80\n";
        assert!(matches!(
            Params::from_toml_str(source),
            Err(ParamsError::Invalid(_))
        ));
    }
}
