import { api } from './api'
import type { Rule } from './types'

// As regras de conteúdo mudam só por RFC, então uma busca por sessão basta.
let cached: Promise<Rule[]> | null = null

export function loadRules(): Promise<Rule[]> {
  cached ??= api.rules().then(({ rules }) => rules)
  cached.catch(() => {
    cached = null
  })
  return cached
}
