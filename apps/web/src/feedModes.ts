// Os mesmos modos de services/feed-engine e proto/feed.proto.
export type FeedMode =
  | 'bubble'
  | 'outside_bubble'
  | 'mixed'
  | 'chronological'
  | 'public_ranking'

export const FEED_MODES: { id: FeedMode; label: string; description: string }[] = [
  {
    id: 'bubble',
    label: 'Na bolha',
    description: 'Mais de quem você segue e dos temas de que você gosta.',
  },
  {
    id: 'outside_bubble',
    label: 'Furando a bolha',
    description: 'Posts bem avaliados de temas que você ainda não acompanha.',
  },
  {
    id: 'mixed',
    label: 'Meio a meio',
    description: 'Um pouco da sua bolha e um pouco de coisa nova, alternando.',
  },
  {
    id: 'chronological',
    label: 'Por data',
    description: 'Só quem você segue, do mais novo para o mais antigo. Sem algoritmo.',
  },
  {
    id: 'public_ranking',
    label: 'Ranking público',
    description: 'A mesma fórmula para todo mundo, publicada junto com o código.',
  },
]
