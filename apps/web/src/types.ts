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
  /** Conta verificada e maior de idade. */
  can_go_live: boolean
  /** Rede de demonstração: mostra os botões que fazem o papel do banco. */
  demo: boolean
  moderator: boolean
  legal_officer: boolean
  unread_notices: number
}

export type PostKind = 'text' | 'photo' | 'video' | 'short' | 'live'

export interface Post {
  id: number
  kind: PostKind
  body: string | null
  /** Foto, ou a lista HLS do vídeo (master.m3u8). */
  media_url: string | null
  /** Vídeo fica "processing" até a fila terminar de converter. */
  media_status: 'ready' | 'processing' | 'failed'
  poster_url: string | null
  captions_url: string | null
  duration_ms: number | null
  width: number | null
  height: number | null
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
  /** A exibição deste anúncio. Só conta anúncio que a rede mostrou. */
  slot_id: number
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
  pix_key: { kind: 'email' | 'phone' | 'random'; hint: string } | null
  statements: StatementSummary[]
}

export type PayoutStatus = 'sending' | 'paid' | 'carried' | 'no_key' | 'failed'

export interface StatementSummary {
  month: string
  total_cents: number
  status: PayoutStatus
  paid_at: string | null
}

/** Um mês fechado, linha a linha. */
export interface Statement {
  month: string
  national_views: number
  regional_views: number
  discarded_views: number
  discarded_by_reason: Record<string, number>
  by_post: { post_id: number; views: number }[]
  weighted_views: number
  effective_views: number
  video_cents: number
  shorts: { id: number; at: number; revenue_cents: number; my_cents: number }[]
  shorts_cents: number
  carry_in_cents: number
  total_cents: number
  payable: boolean
  status: PayoutStatus
  pix_key_hint: string | null
  pix_e2e_id: string | null
  paid_at: string | null
  root: string
  registro_position: number | null
  lines: number
}

export interface Advertiser {
  id: number
  name: string
  cnpj: string
}

export interface AdRule {
  number: number
  title: string
  text: string
}

export type CampaignStatus = 'in_review' | 'awaiting_payment' | 'active' | 'rejected'

/** Uma campanha vista por quem anuncia (ou pela moderação). */
export interface OwnCampaign extends Ad {
  status: CampaignStatus
  hours_per_day: number
  impressions_per_day: number | null
  cents_per_impression: number
  price_cents: number | null
  paid_cents: number
  starts_on: string
  ends_on: string
  rejection_rule: AdRule | null
  brcode: string | null
  charge_txid: string | null
}

export interface CampaignQuote {
  impressions_per_day: number
  days: number
  cents_per_impression: number
  total_cents: number
}

export interface QuarterlyReport {
  quarter: string
  sha256: string
  registro_position: number | null
  published_at: string
}

export interface OpenAccountsMonth {
  month: string
  revenue_cents: number
  creators_cents: number
  fund_cents: number
  root: string
  registro_position: number | null
}

export interface ParamsFile {
  path: string
  version: number
  sha256: string
  source: string
}

export interface WatchCost {
  short_side: number
  gb_per_hour: number
  cents: number
}

export interface VideoCosts {
  prices: {
    storage_cents_per_gb_month: number
    egress_cents_per_gb: number
    cpu_cents_per_hour: number
    months_stored: number
  }
  measured: {
    videos: number
    hours: number
    storage_gb_per_hour?: number
    cpu_hours_per_hour?: number
    store_cents?: number
    transcode_cents?: number
    watch?: WatchCost[]
  }
  ceiling: { storage_gb_per_hour: number; store_cents: number; watch: WatchCost[] }
}

export interface TransparencyReport {
  video: { params: ParamsFile; costs: VideoCosts }
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
    cnpj: string | null
    hours_per_day: number
    cents_per_impression: number
    paid_cents: number
    delivered: number
    starts_on: string
    ends_on: string
  })[]
  ad_rules: AdRule[]
  open_accounts: OpenAccountsMonth[]
  quarterly_reports: QuarterlyReport[]
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

/** O registro público: cabeçalho assinado e as últimas entradas. */
export interface Registro {
  head: { size: number; root: string; timestamp: number; signature: string; public_key: string }
  entries: { index: number; kind: string; data: string; leaf_hash: string; at: string }[]
}
