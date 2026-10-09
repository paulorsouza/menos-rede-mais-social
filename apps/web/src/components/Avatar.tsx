import { BadgeCheck } from 'lucide-react'
import { avatarFor } from '../format'

export function Avatar({ nickname, size = 40 }: { nickname: string; size?: number }) {
  const { initials, hue } = avatarFor(nickname)
  return (
    <span
      className="avatar"
      aria-hidden="true"
      style={{
        width: size,
        height: size,
        fontSize: Math.round(size * 0.38),
        background: `hsl(${hue} 52% 40%)`,
      }}
    >
      {initials}
    </span>
  )
}

export function Verified({ size = 16 }: { size?: number }) {
  return (
    <span className="verified" title="Pessoa verificada pelo gov.br">
      <BadgeCheck size={size} aria-label="Pessoa verificada pelo gov.br" />
    </span>
  )
}
