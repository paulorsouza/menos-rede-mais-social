import { Link } from 'react-router'
import { Check, ChevronDown, Clock, Compass, Cpu, Shuffle, Sparkles, TriangleAlert, Flame } from 'lucide-react'
import type { LucideIcon } from 'lucide-react'
import { useApp } from '../app-context'
import { FEED_MODES } from '../feedModes'
import type { FeedMode } from '../feedModes'
import type { EngineInfo } from '../types'
import { Popover } from './Popover'

export const MODE_ICONS: Record<FeedMode, LucideIcon> = {
  bubble: Sparkles,
  outside_bubble: Compass,
  mixed: Shuffle,
  chronological: Clock,
  public_ranking: Flame,
}

export function ModePicker({ glass = false }: { glass?: boolean }) {
  const { mode, setMode } = useApp()
  const current = FEED_MODES.find((option) => option.id === mode) ?? FEED_MODES[0]
  const Icon = MODE_ICONS[current.id]

  return (
    <Popover
      label="Modo do feed"
      align="end"
      buttonClassName={`pill-button ${glass ? 'pill-glass' : ''}`}
      button={
        <>
          <Icon size={16} />
          <span>{current.label}</span>
          <ChevronDown size={14} className="pill-caret" />
        </>
      }
    >
      {(close) => (
        <div className="menu">
          <p className="menu-title">Como ver o seu feed</p>
          {FEED_MODES.map((option) => {
            const OptionIcon = MODE_ICONS[option.id]
            const active = option.id === mode
            return (
              <button
                key={option.id}
                type="button"
                className={`menu-item ${active ? 'is-active' : ''}`}
                onClick={() => {
                  setMode(option.id)
                  close()
                }}
              >
                <OptionIcon size={18} />
                <span>
                  <strong>{option.label}</strong>
                  <small>{option.description}</small>
                </span>
                {active && <Check size={16} className="menu-check" />}
              </button>
            )
          })}
        </div>
      )}
    </Popover>
  )
}

/** Mostra, quando pedido, que a ordem veio do motor aberto e com quais parâmetros. */
export function EngineChip({ engine }: { engine: EngineInfo }) {
  const offline = engine.status === 'offline'

  return (
    <Popover
      label="Quem calculou este feed"
      align="end"
      buttonClassName={`icon-btn ${offline ? 'is-warning' : ''}`}
      button={offline ? <TriangleAlert size={18} /> : <Cpu size={18} />}
      panelClassName="pop-text"
    >
      {() =>
        offline ? (
          <p>O motor está fora do ar. Mostrando só quem você segue, por data, sem algoritmo.</p>
        ) : (
          <>
            <p>
              Ordem calculada pelo motor aberto <strong>v{engine.version}</strong>, com os parâmetros públicos{' '}
              <strong>v{engine.params_version}</strong>.
            </p>
            <code className="hash-inline">{engine.params_sha256?.slice(0, 16)}…</code>
            <Link to="/transparencia" className="text-link">
              Conferir na transparência
            </Link>
          </>
        )
      }
    </Popover>
  )
}
