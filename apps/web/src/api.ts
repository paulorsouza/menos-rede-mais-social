import type { FeedMode } from './feedModes'
import type {
  AdRule,
  Advertiser,
  AppealItem,
  CampaignQuote,
  OwnCampaign,
  Statement,
  Dashboard,
  IdentificationOrder,
  FeedResponse,
  GovBrLevel,
  Me,
  Notice,
  OpenedOrder,
  Post,
  Registro,
  Profile,
  QueueEntry,
  Rule,
  ShortsResponse,
  TransparencyReport,
} from './types'

export class ApiError extends Error {
  status: number
  body: unknown

  constructor(status: number, body: unknown) {
    super(messageFrom(body) ?? `Erro ${status}`)
    this.status = status
    this.body = body
  }

  /** Erros de validação no formato { errors: { campo: [mensagens] } }. */
  get fieldErrors(): Record<string, string[]> {
    const body = this.body as { errors?: Record<string, string[]> } | null
    return body?.errors ?? {}
  }
}

function messageFrom(body: unknown): string | undefined {
  if (body && typeof body === 'object' && 'error' in body) {
    return String((body as { error: unknown }).error)
  }
  return undefined
}

async function request<T>(path: string, init: RequestInit = {}): Promise<T> {
  const isForm = init.body instanceof FormData
  const response = await fetch(`/api${path}`, {
    credentials: 'same-origin',
    ...init,
    headers: {
      Accept: 'application/json',
      ...(init.body && !isForm ? { 'Content-Type': 'application/json' } : {}),
      ...init.headers,
    },
  })

  if (response.status === 204) return undefined as T
  const body = await response.json().catch(() => null)
  if (!response.ok) throw new ApiError(response.status, body)
  return body as T
}

const post = <T>(path: string, body?: unknown) =>
  request<T>(path, { method: 'POST', body: body === undefined ? undefined : JSON.stringify(body) })

/** Uma live aberta: os dois jeitos de transmitir. A chave só vem aqui. */
export interface LiveInfo {
  id: string
  post_id: number
  key: string
  whip_url: string
  /** Sem servidor configurado, o RTMP fica no mesmo endereço do app. */
  rtmp: { server: string | null; stream_key: string }
}

export interface RegisterParams {
  cpf: string
  nickname: string
  govbr_level: GovBrLevel
  age_band: 'adult' | 'minor'
  region: string
  bio?: string
}

export const api = {
  me: () => request<{ account: Me | null }>('/me'),
  personas: () => request<{ personas: Me[] }>('/demo/personas'),
  login: (nickname: string) => post<{ account: Me }>('/session', { nickname }),
  logout: () => request<{ ok: true }>('/session', { method: 'DELETE' }),
  testCpf: () => request<{ cpf: string }>('/govbr-simulado/cpf-de-teste'),
  govbrStatus: () => request<{ enabled: boolean }>('/govbr/status'),
  govbrRegister: (params: { nickname: string; region: string }) =>
    post<{ account: Me }>('/govbr/cadastro', params),
  register: (params: RegisterParams) => post<{ account: Me }>('/govbr-simulado/cadastro', params),
  registerBasic: (params: { nickname: string; region: string }) =>
    post<{ account: Me }>('/govbr-simulado/conta-basica', params),

  feed: (mode: FeedMode, kind: 'home' | 'videos' | 'all' = 'home') =>
    request<FeedResponse>(`/feed?mode=${mode}&kind=${kind}`),
  shorts: (mode: FeedMode) => request<ShortsResponse>(`/shorts?mode=${mode}`),

  createPost: (params: {
    body: string
    upload_id?: string
    kind?: string
    alt_text?: string
    ad_markers?: string[]
    monetized?: boolean
  }) => post<{ post: Post }>('/posts', params),
  getPost: (id: number) => request<{ post: Post }>(`/posts/${id}`),
  createLive: (body: string) => post<{ live: LiveInfo }>('/lives', { body }),
  like: (id: number) => post<{ liked: boolean; likes: number; saves: number }>(`/posts/${id}/like`),
  save: (id: number) => post<{ saved: boolean; likes: number; saves: number }>(`/posts/${id}/save`),
  view: (id: number, watchedMs: number) =>
    post<void>(`/posts/${id}/views`, { watched_ms: Math.round(watchedMs) }),

  profile: (nickname: string) => request<Profile>(`/accounts/${encodeURIComponent(nickname)}`),
  follow: (nickname: string) =>
    post<{ following: boolean; counts: Profile['counts'] }>(
      `/accounts/${encodeURIComponent(nickname)}/follow`,
    ),

  /** Um anúncio passou dentro de um vídeo, num ponto que o criador marcou. */
  adView: (slotId: number, postId: number, moment: string) =>
    post<void>('/ads/views', { slot_id: slotId, post_id: postId, moment }),

  impression: (slotId: number, watched: { post_id: number; watched_ms: number }[]) =>
    post<{ revenue_cents: number; splits: Record<string, number> }>('/ads/impressions', {
      slot_id: slotId,
      watched,
    }),

  rules: () => request<{ rules: Rule[] }>('/moderation/rules'),
  report: (postId: number, rule: number) => post<{ ok: true }>(`/posts/${postId}/report`, { rule }),
  appeal: (postId: number, text: string) => post<{ ok: true }>(`/posts/${postId}/appeal`, { text }),
  notices: () => request<{ notices: Notice[] }>('/me/notices'),
  deleteAccount: (nickname: string) =>
    request<{ ok: true }>('/me', { method: 'DELETE', body: JSON.stringify({ nickname }) }),
  readNotices: () => post<{ ok: true }>('/me/notices/read'),
  moderationQueue: () =>
    request<{ reports: QueueEntry[]; appeals: AppealItem[]; campaigns: OwnCampaign[]; ad_rules: AdRule[] }>(
      '/moderation/queue',
    ),
  approveCampaign: (id: number) => post<{ ok: true }>(`/moderation/campaigns/${id}/approve`),
  rejectCampaign: (id: number, rule: number) => post<{ ok: true }>(`/moderation/campaigns/${id}/reject`, { rule }),
  removePost: (postId: number, rule: number) => post<{ ok: true }>(`/moderation/posts/${postId}/remove`, { rule }),
  keepPost: (postId: number) => post<{ ok: true }>(`/moderation/posts/${postId}/keep`),
  decideAppeal: (appealId: number, outcome: 'restore' | 'uphold') =>
    post<{ ok: true }>(`/moderation/appeals/${appealId}/decide`, { outcome }),

  orders: () => request<{ orders: IdentificationOrder[]; demo: boolean }>('/identification/orders'),
  createOrder: (order: { nickname: string; court: string; case_number: string; secret_case: boolean }) =>
    post<{ order: IdentificationOrder }>('/identification/orders', order),
  simulateGuardian: (orderId: number, guardian: number) =>
    post<{ order: IdentificationOrder }>(`/identification/orders/${orderId}/simulate/${guardian}`),
  openOrder: (orderId: number) =>
    post<{ result: OpenedOrder; order: IdentificationOrder }>(`/identification/orders/${orderId}/open`),

  dashboard: () => request<Dashboard>('/creator/dashboard'),
  setPixKey: (key: string) => post<{ pix_key: { kind: string; hint: string } }>('/creator/pix', { key }),
  statement: (month: string) => request<{ statement: Statement }>(`/creator/statements/${month}`),

  advertiser: () => request<{ advertiser: Advertiser | null; campaigns: OwnCampaign[] }>('/anunciante'),
  registerAdvertiser: (cnpj: string, name: string) =>
    post<{ advertiser: Advertiser }>('/anunciante', { cnpj, name }),
  quoteCampaign: (campaign: Record<string, string>) =>
    post<{ quote: CampaignQuote }>('/anunciante/orcamento', campaign),
  createCampaign: (campaign: Record<string, string>) =>
    post<{ campaign: OwnCampaign }>('/anunciante/campanhas', campaign),
  testCnpj: () => request<{ cnpj: string }>('/demo/cnpj-de-teste'),
  payCharge: (txid: string) => post<{ ok: true }>(`/demo/pix/${txid}/pagar`),
  transparency: () => request<TransparencyReport>('/transparency'),
  registro: () => request<Registro>('/registro'),
}
