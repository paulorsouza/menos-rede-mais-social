import type { FeedMode } from './feedModes'

export type Reason =
  | { kind: 'you_follow' }
  | { kind: 'follows_engaged'; value: number }
  | { kind: 'similar_engaged'; value: number }
  | { kind: 'outside_bubble' }
  | { kind: 'public_ranking' }

export interface Author {
  id: string
  nickname: string
  bio: string | null
  region: string | null
  verified: boolean
}

export type GovBrLevel = 'bronze' | 'prata' | 'ouro'

export interface Me extends Author {
  govbr_level: GovBrLevel | null
  can_publish: boolean
  can_monetize: boolean
  moderator: boolean
  legal_officer: boolean
  unread_notices: number
}

export type PostKind = 'text' | 'photo' | 'video' | 'short'

export interface Post {
  id: number
  kind: PostKind
  body: string | null
  media_url: string | null
  alt_text: string | null
  monetized: boolean
  ad_markers: string[]
  created_at: string
  author: Author
  likes: number
  saves: number
  views: number
  liked: boolean
  saved: boolean
  reasons: Reason[]
}

export interface EngineInfo {
  status: 'ok' | 'offline'
  version?: string
  build?: string
  params_version?: number
  params_sha256?: string
}

export interface Ad {
  id: number
  advertiser: string
  title: string
  body: string | null
  cta: string | null
  color: string | null
  scope: 'national' | 'regional'
  region: string | null
}

export interface FeedResponse {
  mode: FeedMode
  engine: EngineInfo
  items: Post[]
  ad?: Ad | null
}

export type ShortItem =
  | { type: 'short'; post: Post }
  | { type: 'ad'; ad: Ad; short_ids: number[] }

export interface ShortsResponse {
  mode: FeedMode
  engine: EngineInfo
  ad_every: number
  items: ShortItem[]
}

export interface Profile {
  account: Author
  counts: { posts: number; followers: number; following: number }
  following: boolean
  /** Perfil de menor de idade que não segue quem está vendo. */
  private: boolean
  posts: Post[]
}

export interface PayoutBand {
  up_to: number | null
  percent: number
}

export interface Dashboard {
  month: string
  monetizable: boolean
  views: number
  cents_per_thousand: number
  effective_views: number
  payout_cents: number
  params_version: number
  bands: PayoutBand[]
  current_band: number
  shorts: {
    total_cents: number
    count: number
    recent: {
      at: string
      advertiser: string
      scope: 'national' | 'regional'
      revenue_cents: number
      my_cents: number
      my_watched_ms: number
      total_watched_ms: number
      creators: number
    }[]
  }
}

export interface ParamsFile {
  path: string
  version: number
  sha256: string
  source: string
}

export interface TransparencyReport {
  engine: {
    status: 'ok' | 'offline'
    engine_version?: string
    engine_build?: string
    feed_params?: ParamsFile
    ads_params?: ParamsFile
    guardians_params?: ParamsFile
    payout_bands?: PayoutBand[]
    shorts_ad_every?: number
  }
  accounts: { verified: number; basic: number }
  posts: Partial<Record<PostKind, number>>
  removals: number
  moderation: {
    removals_by_rule: Record<string, number>
    kept: number
    appeals: { restored: number; upheld: number; pending: number }
  }
  rules: Rule[]
  identifications: {
    requested: number
    opened: number
    secret: number
    entries: { opened_at: string; court: string; case_number: string | null }[]
  }
  ads: (Ad & {
    hours_per_day: number
    cents_per_impression: number
    paid_cents: number
    starts_on: string
    ends_on: string
  })[]
}

/** Uma regra de conteúdo. Toda remoção cita uma delas. */
export interface Rule {
  number: number
  title: string
  text: string
  example: string
  law: string
  reportable: boolean
}

/** Aviso da moderação para quem publicou. */
export interface Notice {
  id: number
  kind: 'removed' | 'restored' | 'upheld'
  rule: Rule | null
  created_at: string
  read: boolean
  post: Post | null
  appeal: null | 'pending' | 'restore' | 'uphold'
  can_appeal: boolean
}

/** Um post na fila de denúncias. */
export interface QueueEntry {
  post: Post
  total: number
  since: string
  reports: { rule: number; count: number; title: string }[]
}

/** Um recurso esperando decisão da moderação. */
export interface AppealItem {
  id: number
  text: string | null
  created_at: string
  rule: Rule | null
  removed_by: Author | null
  post: Post
}

/** Uma ordem judicial de identificação, para o setor jurídico. */
export interface IdentificationOrder {
  id: number
  nickname: string | null
  court: string
  case_number: string | null
  secret_case: boolean
  status: 'collecting' | 'opened'
  created_at: string
  opened_at: string | null
  ready_guardians: number[]
  items: number
}

/** O que uma ordem aberta mostra, uma única vez. */
export interface OpenedOrder {
  cpf: string | null
  accesses: { at: string; ip: string }[]
}
