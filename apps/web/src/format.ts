const relative = new Intl.RelativeTimeFormat('pt-BR', { numeric: 'auto' })
const money = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' })
const number = new Intl.NumberFormat('pt-BR')
const compact = new Intl.NumberFormat('pt-BR', { notation: 'compact', maximumFractionDigits: 1 })

export function timeAgo(iso: string): string {
  const seconds = Math.round((new Date(iso).getTime() - Date.now()) / 1000)
  const minutes = Math.round(seconds / 60)
  const hours = Math.round(minutes / 60)
  const days = Math.round(hours / 24)

  if (Math.abs(seconds) < 60) return 'agora'
  if (Math.abs(minutes) < 60) return relative.format(minutes, 'minute')
  if (Math.abs(hours) < 24) return relative.format(hours, 'hour')
  return relative.format(days, 'day')
}

export const formatMoney = (cents: number) => money.format(cents / 100)
export const formatNumber = (value: number) => number.format(value)
export const formatCompact = (value: number) => compact.format(value)

export function monthName(iso: string): string {
  return new Date(`${iso}T12:00:00`).toLocaleDateString('pt-BR', { month: 'long', year: 'numeric' })
}

/** Aceita só a data ("2026-10-09") ou data e hora completas. */
export function formatDate(iso: string): string {
  const date = iso.includes('T') ? new Date(iso) : new Date(`${iso}T12:00:00`)
  return date.toLocaleDateString('pt-BR')
}

/** Data e hora, para registros em que a hora importa (como os acessos). */
export function formatDateTime(iso: string): string {
  return new Date(iso).toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' })
}

/** Iniciais e cor do avatar, sempre as mesmas para o mesmo apelido. */
export function avatarFor(nickname: string) {
  const parts = nickname.split(/[._]/).filter(Boolean)
  const initials = (parts.length > 1 ? parts[0][0] + parts[1][0] : nickname.slice(0, 2)).toUpperCase()
  let hash = 0
  for (const char of nickname) hash = (hash * 31 + char.charCodeAt(0)) >>> 0
  return { initials, hue: hash % 360 }
}
