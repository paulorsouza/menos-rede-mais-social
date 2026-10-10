//! Entrega das exibições ao longo do dia e pelo país.
//!
//! O anunciante compra horas de exibição por dia. Sem ritmo, a campanha
//! gastaria tudo de manhã, para quem acordou cedo. Aqui, cada campanha só pode
//! ter mostrado, até agora, a parte do dia que já passou, pesada pela
//! audiência de cada hora (`hourly_weights`). E o anúncio nacional não pode
//! gastar numa região mais do que a parte dela na audiência do dia.
//!
//! Entre as campanhas que ainda cabem, sai a mais atrasada em relação ao
//! ritmo. Empate: a regional antes da nacional (o comércio do bairro primeiro)
//! e depois o menor id. Nada aqui olha quem é a pessoa, só a cidade dela.

use serde::{Deserialize, Serialize};

use crate::Delivery;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Scope {
    National,
    Regional,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Candidate {
    pub id: u64,
    pub scope: Scope,
    /// Cidade da campanha regional. Nacional não tem.
    #[serde(default)]
    pub region: Option<String>,
    /// Exibições compradas para o dia.
    pub daily_budget: u64,
    pub delivered_today: u64,
    /// Exibições de hoje para gente da mesma cidade de quem vai ver agora.
    pub delivered_in_region_today: u64,
}

/// A audiência de hoje: quanto dela é da cidade de quem vai ver agora.
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct Audience {
    pub region: u64,
    pub total: u64,
}

/// Quantas exibições a campanha já pode ter mostrado a esta altura do dia.
pub fn allowance(daily_budget: u64, seconds_into_day: u32, delivery: &Delivery) -> u64 {
    let weights = &delivery.hourly_weights;
    let total: u64 = weights.iter().map(|&w| u64::from(w)).sum();
    let seconds = u64::from(seconds_into_day.min(86_399));
    let hour = (seconds / 3600) as usize;

    // Peso das horas inteiras que já passaram, mais a fração da hora atual,
    // tudo em "segundos-peso" para ficar em números inteiros.
    let done: u64 = weights[..hour]
        .iter()
        .map(|&w| u64::from(w) * 3600)
        .sum::<u64>()
        + u64::from(weights[hour]) * (seconds % 3600);

    let paced = u128::from(daily_budget) * u128::from(done) / u128::from(total * 3600);
    let with_headroom = paced * u128::from(100 + delivery.headroom_percent) / 100 + 1;
    with_headroom.min(u128::from(daily_budget)) as u64
}

/// Escolhe a campanha de cada um dos próximos `slots` anúncios para alguém
/// desta cidade, contando cada escolha como entregue para a seguinte.
pub fn pick(
    viewer_region: &str,
    seconds_into_day: u32,
    audience: Audience,
    candidates: &[Candidate],
    delivery: &Delivery,
    slots: usize,
) -> Vec<u64> {
    let mut eligible: Vec<Candidate> = candidates
        .iter()
        .filter(|c| match c.scope {
            Scope::National => true,
            Scope::Regional => c.region.as_deref() == Some(viewer_region),
        })
        .cloned()
        .collect();

    let mut picked = Vec::with_capacity(slots);
    for _ in 0..slots {
        let best = eligible
            .iter_mut()
            .filter_map(|c| {
                let allowed = allowance(c.daily_budget, seconds_into_day, delivery);
                if c.delivered_today >= allowed {
                    return None;
                }
                if c.scope == Scope::National && audience.total > 0 {
                    let share = u128::from(allowed) * u128::from(audience.region)
                        / u128::from(audience.total);
                    let cap = share * u128::from(100 + delivery.region_headroom_percent) / 100 + 1;
                    if u128::from(c.delivered_in_region_today) >= cap {
                        return None;
                    }
                }
                // Quanto do permitido já foi usado, em milésimos: menor é mais atrasada.
                let used = c.delivered_today * 1000 / allowed.max(1);
                let regional_first = u8::from(c.scope == Scope::National);
                Some(((used, regional_first, c.id), c))
            })
            .min_by_key(|(key, _)| *key);

        match best {
            Some((_, campaign)) => {
                campaign.delivered_today += 1;
                campaign.delivered_in_region_today += 1;
                picked.push(campaign.id);
            }
            None => break,
        }
    }
    picked
}

#[cfg(test)]
mod tests {
    use super::*;

    fn delivery() -> Delivery {
        crate::Params::from_toml_str(include_str!("../../../params/ads.toml"))
            .unwrap()
            .delivery
    }

    fn flat() -> Delivery {
        Delivery {
            hourly_weights: vec![1; 24],
            headroom_percent: 0,
            region_headroom_percent: 0,
        }
    }

    fn campaign(
        id: u64,
        scope: Scope,
        region: Option<&str>,
        budget: u64,
        delivered: u64,
    ) -> Candidate {
        Candidate {
            id,
            scope,
            region: region.map(str::to_string),
            daily_budget: budget,
            delivered_today: delivered,
            delivered_in_region_today: 0,
        }
    }

    const ALL: Audience = Audience {
        region: 1,
        total: 1,
    };

    #[test]
    fn a_flat_day_releases_the_budget_by_the_hour() {
        // Meio-dia de um dia sem pesos diferentes: metade do orçamento, mais 1.
        assert_eq!(allowance(2400, 12 * 3600, &flat()), 1201);
        assert_eq!(allowance(2400, 0, &flat()), 1);
        assert_eq!(allowance(2400, 86_399, &flat()), 2400);
    }

    #[test]
    fn the_night_releases_less_than_the_evening() {
        let delivery = delivery();
        let night =
            allowance(100_000, 4 * 3600, &delivery) - allowance(100_000, 3 * 3600, &delivery);
        let evening =
            allowance(100_000, 20 * 3600, &delivery) - allowance(100_000, 19 * 3600, &delivery);
        assert!(evening > night * 5);
    }

    #[test]
    fn a_campaign_ahead_of_its_pace_waits() {
        let candidates = [campaign(1, Scope::National, None, 2400, 1201)];
        assert!(pick("Campinas/SP", 12 * 3600, ALL, &candidates, &flat(), 1).is_empty());
    }

    #[test]
    fn the_most_behind_goes_first_and_regional_wins_ties() {
        let candidates = [
            campaign(1, Scope::National, None, 1000, 400),
            campaign(2, Scope::National, None, 1000, 100),
            campaign(3, Scope::Regional, Some("Campinas/SP"), 1000, 100),
            campaign(4, Scope::Regional, Some("Recife/PE"), 1000, 0),
        ];
        let picked = pick("Campinas/SP", 12 * 3600, ALL, &candidates, &flat(), 3);
        // A de Recife não vale para quem é de Campinas.
        assert_eq!(picked, vec![3, 2, 3]);
    }

    #[test]
    fn a_national_ad_does_not_drain_one_city() {
        // Campinas é 10% da audiência; a campanha já gastou ali o que cabia.
        let mut candidate = campaign(1, Scope::National, None, 2400, 100);
        candidate.delivered_in_region_today = 121;
        let audience = Audience {
            region: 10,
            total: 100,
        };
        assert!(
            pick(
                "Campinas/SP",
                12 * 3600,
                audience,
                &[candidate.clone()],
                &flat(),
                1
            )
            .is_empty()
        );

        candidate.delivered_in_region_today = 60;
        assert_eq!(
            pick("Campinas/SP", 12 * 3600, audience, &[candidate], &flat(), 1),
            vec![1]
        );
    }
}
