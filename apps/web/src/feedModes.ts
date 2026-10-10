// Os mesmos modos de services/feed-engine e proto/feed.proto.
export type FeedMode =
  | 'bubble'
  | 'outside_bubble'
  | 'mixed'
  | 'chronological'
  | 'public_ranking'

// "Em alta" (public_ranking) não entra no seletor: tem aba própria, igual
// para todo mundo.
export const FEED_MODES: { id: FeedMode; label: string; description: string }[] = [
  {
    id: 'bubble',
    label: 'Na bolha',
    description: 'Quem você segue e o que curtem as pessoas que curtem o que você curte.',
  },
  {
    id: 'outside_bubble',
    label: 'Furando a bolha',
    description: 'Só o que ninguém perto de você curtiu ou assistiu. Um autor de cada vez.',
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
]
