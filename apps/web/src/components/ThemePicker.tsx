import { Palette } from 'lucide-react'
import { useApp } from '../app-context'
import { THEMES } from '../theme'
import { Popover } from './Popover'

export function ThemeSwatches() {
  const { theme, setTheme } = useApp()

  return (
    <div className="swatches" role="radiogroup" aria-label="Tema">
      {THEMES.map((option) => (
        <button
          key={option.id}
          type="button"
          role="radio"
          aria-checked={theme === option.id}
          className="swatch"
          onClick={() => setTheme(option.id)}
        >
          <span
            className="swatch-dot"
            style={{ background: `linear-gradient(135deg, ${option.swatch[0]} 50%, ${option.swatch[1]} 50%)` }}
          />
          <span className="swatch-label">{option.label}</span>
        </button>
      ))}
    </div>
  )
}

export function ThemePicker({ placement = 'bottom', align = 'end' }: { placement?: 'bottom' | 'top' | 'right'; align?: 'start' | 'end' }) {
  return (
    <Popover label="Tema" button={<Palette size={19} />} buttonClassName="icon-btn" placement={placement} align={align}>
      {() => (
        <div className="menu">
          <p className="menu-title">Tema</p>
          <ThemeSwatches />
        </div>
      )}
    </Popover>
  )
}
