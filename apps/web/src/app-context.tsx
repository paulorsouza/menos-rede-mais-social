import { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react'
import type { ReactNode } from 'react'
import { api } from './api'
import { FEED_MODES } from './feedModes'
import type { FeedMode } from './feedModes'
import { applyTheme, initialTheme } from './theme'
import type { Theme } from './theme'
import type { Me, Post } from './types'

type ToastTone = 'info' | 'success' | 'error'

interface Toast {
  id: number
  message: string
  tone: ToastTone
}

interface AppState {
  me: Me | null
  loadingMe: boolean
  setMe: (me: Me | null) => void
  logout: () => Promise<void>
  mode: FeedMode
  setMode: (mode: FeedMode) => void
  theme: Theme
  setTheme: (theme: Theme) => void
  toast: (message: string, tone?: ToastTone) => void
  published: Post[]
  addPublished: (post: Post) => void
}

const AppContext = createContext<AppState | null>(null)

const MODE_KEY = 'rede-social:modo-do-feed'

function storedMode(): FeedMode {
  try {
    const value = localStorage.getItem(MODE_KEY)
    const known = FEED_MODES.find((option) => option.id === value)
    if (known) return known.id
  } catch {
    // Sem acesso ao armazenamento do navegador: usa o padrão.
  }
  return 'mixed'
}

export function AppProvider({ children }: { children: ReactNode }) {
  const [me, setMe] = useState<Me | null>(null)
  const [loadingMe, setLoadingMe] = useState(true)
  const [mode, setModeState] = useState<FeedMode>(storedMode)
  const [theme, setThemeState] = useState<Theme>(initialTheme)
  const [toasts, setToasts] = useState<Toast[]>([])
  const [published, setPublished] = useState<Post[]>([])

  useEffect(() => {
    api
      .me()
      .then(({ account }) => setMe(account))
      .catch(() => setMe(null))
      .finally(() => setLoadingMe(false))
  }, [])

  useEffect(() => applyTheme(theme), [theme])

  const toast = useCallback((message: string, tone: ToastTone = 'info') => {
    const id = Date.now() + Math.random()
    setToasts((current) => [...current, { id, message, tone }])
    setTimeout(() => setToasts((current) => current.filter((t) => t.id !== id)), 3600)
  }, [])

  const setMode = useCallback((next: FeedMode) => {
    setModeState(next)
    try {
      localStorage.setItem(MODE_KEY, next)
    } catch {
      // Sem acesso ao armazenamento: o modo vale só nesta aba.
    }
  }, [])

  const logout = useCallback(async () => {
    await api.logout().catch(() => undefined)
    setMe(null)
    setPublished([])
  }, [])

  const addPublished = useCallback((post: Post) => setPublished((current) => [post, ...current]), [])

  const value = useMemo(
    () => ({
      me,
      loadingMe,
      setMe,
      logout,
      mode,
      setMode,
      theme,
      setTheme: setThemeState,
      toast,
      published,
      addPublished,
    }),
    [me, loadingMe, logout, mode, setMode, theme, toast, published, addPublished],
  )

  return (
    <AppContext.Provider value={value}>
      {children}
      <div className="toasts" role="status" aria-live="polite">
        {toasts.map((t) => (
          <div key={t.id} className={`toast toast-${t.tone}`}>
            {t.message}
          </div>
        ))}
      </div>
    </AppContext.Provider>
  )
}

export function useApp() {
  const context = useContext(AppContext)
  if (!context) throw new Error('useApp precisa estar dentro de AppProvider')
  return context
}
