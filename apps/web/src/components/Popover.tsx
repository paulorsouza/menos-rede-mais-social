import { useEffect, useRef, useState } from 'react'
import type { ReactNode } from 'react'
import { Info } from 'lucide-react'

interface PopoverProps {
  label: string
  button: ReactNode
  buttonClassName?: string
  align?: 'start' | 'end'
  placement?: 'bottom' | 'top' | 'right'
  panelClassName?: string
  children: (close: () => void) => ReactNode
}

/** Botão que abre um painel. Fecha ao clicar fora ou apertar Esc. */
export function Popover({
  label,
  button,
  buttonClassName = 'pill-button',
  align = 'start',
  placement = 'bottom',
  panelClassName = '',
  children,
}: PopoverProps) {
  const [open, setOpen] = useState(false)
  const ref = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!open) return
    const onPointer = (event: PointerEvent) => {
      if (!ref.current?.contains(event.target as Node)) setOpen(false)
    }
    const onKey = (event: KeyboardEvent) => event.key === 'Escape' && setOpen(false)
    document.addEventListener('pointerdown', onPointer)
    document.addEventListener('keydown', onKey)
    return () => {
      document.removeEventListener('pointerdown', onPointer)
      document.removeEventListener('keydown', onKey)
    }
  }, [open])

  return (
    <div className="popover" ref={ref}>
      <button
        type="button"
        className={buttonClassName}
        aria-label={label}
        aria-expanded={open}
        aria-haspopup="dialog"
        onClick={() => setOpen((value) => !value)}
      >
        {button}
      </button>
      {open && (
        <div className={`pop pop-${placement} pop-${align} ${panelClassName}`} role="dialog" aria-label={label}>
          {children(() => setOpen(false))}
        </div>
      )}
    </div>
  )
}

/** Explicação que só aparece quando a pessoa pede. */
export function InfoTip({ children, label = 'Saiba mais', align = 'end' }: { children: ReactNode; label?: string; align?: 'start' | 'end' }) {
  return (
    <Popover label={label} button={<Info size={17} />} buttonClassName="icon-btn icon-btn-sm" align={align} panelClassName="pop-text">
      {() => children}
    </Popover>
  )
}
