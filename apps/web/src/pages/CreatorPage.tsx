import { useEffect, useState } from 'react'
import type { CSSProperties } from 'react'
import { ChevronDown } from 'lucide-react'
import { api } from '../api'
import { PageHead } from '../components/Layout'
import { PixKeyCard, Statements } from '../components/Payouts'
import { InfoTip } from '../components/Popover'
import { ErrorState, Loading } from '../components/States'
import { formatCompact, formatMoney, formatNumber, monthName, timeAgo } from '../format'
import type { Dashboard, PayoutBand } from '../types'

function bandLabel(bands: PayoutBand[], index: number) {
  const from = index === 0 ? 0 : (bands[index - 1].up_to ?? 0)
  const to = bands[index].up_to
  if (to === null) return `+${formatCompact(from)}`
  return `${formatCompact(from)}–${formatCompact(to)}`
}

/** Quantas views do criador caem em cada faixa. Só para mostrar a conta. */
function viewsInBands(bands: PayoutBand[], views: number) {
  let floor = 0
  return bands.map((band) => {
    const ceiling = Math.min(band.up_to ?? Infinity, views)
    const inBand = Math.max(ceiling - floor, 0)
    floor = Math.max(floor, ceiling)
    return inBand
  })
}

/** Posição da pessoa dentro da própria faixa, de 0 a 1. Cada faixa ocupa o mesmo espaço na barra. */
function markerPosition(bands: PayoutBand[], views: number, current: number) {
  const from = current === 0 ? 0 : (bands[current - 1].up_to ?? 0)
  const to = bands[current].up_to ?? from * 10
  const inside = Math.min(Math.max((views - from) / Math.max(to - from, 1), 0), 1)
  return (current + inside) / bands.length
}

export function CreatorPage() {
  const [data, setData] = useState<Dashboard | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [showMath, setShowMath] = useState(false)

  function load() {
    api
      .dashboard()
      .then(setData)
      .catch((e: Error) => setError(e.message))
  }

  useEffect(load, [])

  if (error) return <div className="page"><ErrorState message={error} /></div>
  if (!data) return <div className="page"><Loading /></div>

  const distribution = viewsInBands(data.bands, data.views)
  const position = markerPosition(data.bands, data.views, data.current_band)

  return (
    <div className="page">
      <PageHead title="Criador">
        <InfoTip label="Sobre os valores">
          Conta a view em que o anúncio passou. O valor por view cai conforme o criador cresce, para abrir espaço para
          quem está começando, e cada faixa vale só para as views dentro dela: crescer nunca diminui o total. O número
          do mês é uma estimativa; a conta de verdade sai no fechamento, com as regras do antifraude. Os valores de
          params/ads.toml são ilustrativos.
        </InfoTip>
      </PageHead>

      <section className="hero-number">
        <span className="hero-label">{monthName(data.month)} · estimativa</span>
        <strong>{formatMoney(data.payout_cents)}</strong>
        <span className="hero-sub">
          {formatNumber(data.views)} views com anúncio · {formatNumber(data.effective_views)} pagas
        </span>
        {!data.monetizable && <span className="badge badge-warning">gov.br bronze não recebe</span>}
      </section>

      <section className="bands">
        <div className="bands-bar">
          {data.bands.map((band, index) => (
            <span key={index} className={`band ${index === data.current_band ? 'is-current' : ''} ${index < data.current_band ? 'is-past' : ''}`}>
              <span className="band-percent">{band.percent}%</span>
            </span>
          ))}
          <span className="bands-marker" style={{ '--pos': position } as CSSProperties} />
        </div>
        <div className="bands-labels">
          {data.bands.map((_, index) => (
            <span key={index}>{bandLabel(data.bands, index)}</span>
          ))}
        </div>

        <button type="button" className="disclosure" onClick={() => setShowMath((value) => !value)} aria-expanded={showMath}>
          Ver a conta <ChevronDown size={16} />
        </button>
        {showMath && (
          <table className="table">
            <tbody>
              {data.bands.map((band, index) => (
                <tr key={index} className={index === data.current_band ? 'is-current' : ''}>
                  <td>{bandLabel(data.bands, index)}</td>
                  <td>{formatNumber(distribution[index])} views</td>
                  <td>× {band.percent}%</td>
                </tr>
              ))}
              <tr className="table-total">
                <td>Base</td>
                <td colSpan={2}>{formatMoney(data.cents_per_thousand)} por mil views pagas</td>
              </tr>
            </tbody>
          </table>
        )}
      </section>

      <section className="split-summary">
        <div>
          <span className="hero-label">Rateio dos shorts</span>
          <strong>{formatMoney(data.shorts.total_cents)}</strong>
        </div>
        <span className="faint">
          {data.shorts.count} {data.shorts.count === 1 ? 'anúncio' : 'anúncios'}
        </span>
      </section>

      {data.shorts.recent.length > 0 && (
        <ul className="split-recent">
          {data.shorts.recent.map((item, index) => (
            <li key={index}>
              <span>
                {item.advertiser}
                <small>
                  {timeAgo(item.at)} · {(item.my_watched_ms / 1000).toFixed(0)}s de {(item.total_watched_ms / 1000).toFixed(0)}s
                </small>
              </span>
              <strong>{formatMoney(item.my_cents)}</strong>
            </li>
          ))}
        </ul>
      )}

      {data.monetizable && <PixKeyCard dashboard={data} onSaved={load} />}
      <Statements statements={data.statements} />
    </div>
  )
}
