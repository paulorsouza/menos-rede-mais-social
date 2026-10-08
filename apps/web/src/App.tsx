import { useEffect, useState } from 'react'
import { FEED_MODES, type FeedMode } from './feedModes'

type Section = 'fotos' | 'textos' | 'videos'

const SECTIONS: { id: Section; label: string }[] = [
  { id: 'fotos', label: 'Fotos' },
  { id: 'textos', label: 'Textos' },
  { id: 'videos', label: 'Vídeos' },
]

type BackendStatus = 'checking' | 'online' | 'offline'

const BACKEND_STATUS_TEXT: Record<BackendStatus, string> = {
  checking: 'conferindo o backend…',
  online: 'backend no ar',
  offline: 'backend fora do ar (rode mix phx.server em apps/backend)',
}

export default function App() {
  const [section, setSection] = useState<Section>('fotos')
  const [mode, setMode] = useState<FeedMode>('mixed')
  const [backend, setBackend] = useState<BackendStatus>('checking')

  useEffect(() => {
    fetch('/api/health')
      .then((response) => setBackend(response.ok ? 'online' : 'offline'))
      .catch(() => setBackend('offline'))
  }, [])

  const currentMode = FEED_MODES.find((option) => option.id === mode)

  return (
    <div className="app">
      <header className="topbar">
        <h1 className="logo">-rede+social</h1>
        <nav aria-label="Seções">
          {SECTIONS.map((item) => (
            <button
              key={item.id}
              type="button"
              className="tab"
              aria-pressed={section === item.id}
              onClick={() => setSection(item.id)}
            >
              {item.label}
            </button>
          ))}
        </nav>
      </header>

      <main>
        <fieldset className="feed-mode">
          <legend>Como você quer ver o seu feed?</legend>
          <div className="options">
            {FEED_MODES.map((option) => (
              <label key={option.id} className="option">
                <input
                  type="radio"
                  name="feed-mode"
                  value={option.id}
                  checked={mode === option.id}
                  onChange={() => setMode(option.id)}
                />
                {option.label}
              </label>
            ))}
          </div>
          <p className="hint">{currentMode?.description}</p>
        </fieldset>

        <section className="feed" aria-live="polite">
          <p className="empty">Ainda não tem nada por aqui. Os primeiros posts chegam com o protótipo da Fase 1.</p>
        </section>
      </main>

      <footer className="footer">
        <span className={`status status-${backend}`}>{BACKEND_STATUS_TEXT[backend]}</span>
      </footer>
    </div>
  )
}
