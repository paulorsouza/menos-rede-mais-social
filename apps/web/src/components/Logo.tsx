/**
 * O logo se lê "rede social". O significado vem nos detalhes: "rede" é fino e
 * apagado, "social" é forte, um traço de menos vem antes da palavra rede e um
 * sinal de mais ocupa o espaço entre as duas. Menos rede, mais social.
 *
 * No tema nerd os sinais viram caracteres de verdade, como flags de terminal:
 * -rede +social
 */
export function Wordmark({ size = 'md' }: { size?: 'sm' | 'md' | 'lg' | 'xl' }) {
  return (
    <span className={`wordmark wordmark-${size}`} role="img" aria-label="rede social: menos rede, mais social">
      <span className="wm-minus" aria-hidden="true">
        <span className="wm-glyph">-</span>
      </span>
      <span className="wm-rede" aria-hidden="true">
        rede
      </span>
      <span className="wm-plus" aria-hidden="true">
        <span className="wm-glyph">+</span>
      </span>
      <span className="wm-social" aria-hidden="true">
        social
      </span>
      <span className="wm-cursor" aria-hidden="true" />
    </span>
  )
}

/** A marca compacta: um menos discreto e um mais forte. */
export function LogoMark({ size = 32 }: { size?: number }) {
  return (
    <svg className="logo-mark" width={size} height={size} viewBox="0 0 32 32" aria-hidden="true">
      <rect className="lm-bg" width="32" height="32" rx="9" />
      <rect className="lm-minus" x="5.5" y="15" width="7" height="2" rx="1" />
      <rect className="lm-plus" x="15" y="14" width="12" height="4" rx="2" />
      <rect className="lm-plus" x="19" y="10" width="4" height="12" rx="2" />
    </svg>
  )
}
