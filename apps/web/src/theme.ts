export type Theme = 'light' | 'dark' | 'lime' | 'nerd'

// `swatch` são as duas cores que representam o tema no seletor.
export const THEMES: { id: Theme; label: string; swatch: [string, string] }[] = [
  { id: 'light', label: 'Claro', swatch: ['#ffffff', '#16a34a'] },
  { id: 'dark', label: 'Escuro', swatch: ['#0a0a0b', '#4ade80'] },
  { id: 'lime', label: 'Lima', swatch: ['#050e32', '#cae501'] },
  { id: 'nerd', label: 'Nerd', swatch: ['#050705', '#39ff7a'] },
]

// A mesma chave é lida pelo script do index.html, antes da primeira pintura,
// para a tela não piscar no tema errado.
const THEME_KEY = 'rede-social:tema'

export function initialTheme(): Theme {
  try {
    const saved = localStorage.getItem(THEME_KEY)
    if (saved && THEMES.some((theme) => theme.id === saved)) return saved as Theme
  } catch {
    // Sem acesso ao armazenamento: segue o sistema.
  }
  return window.matchMedia?.('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'
}

export function applyTheme(theme: Theme) {
  document.documentElement.dataset.theme = theme

  // A barra do sistema, no app instalado, acompanha o fundo do tema.
  const background = THEMES.find((option) => option.id === theme)?.swatch[0]
  const meta = document.querySelector('meta[name="theme-color"]')
  if (background && meta) meta.setAttribute('content', background)
  try {
    localStorage.setItem(THEME_KEY, theme)
  } catch {
    // Sem acesso ao armazenamento: o tema vale só nesta aba.
  }
}
