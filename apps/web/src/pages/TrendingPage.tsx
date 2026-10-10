import { useEffect, useState } from 'react'
import { api } from '../api'
import { PageHead } from '../components/Layout'
import { EngineChip } from '../components/ModePicker'
import { InfoTip } from '../components/Popover'
import { PostCard } from '../components/PostCard'
import { Empty, ErrorState, FeedSkeleton } from '../components/States'
import type { FeedResponse } from '../types'

/**
 * O que está em alta, igual para todo mundo. Não olha o grafo de ninguém: é a
 * fórmula pública de params/feed.toml aplicada a todos os posts, de todo tipo.
 * Por isso os posts aqui não têm o "?": a resposta seria sempre a mesma.
 */
export function TrendingPage() {
  const [feed, setFeed] = useState<FeedResponse | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let active = true
    api
      .feed('public_ranking', 'all')
      .then((response) => active && setFeed(response))
      .catch((e: Error) => active && setError(e.message))
    return () => {
      active = false
    }
  }, [])

  return (
    <div className="page">
      <PageHead title="Em alta">
        {feed && <EngineChip engine={feed.engine} account="/api/feed/conta?mode=public_ranking&kind=all" />}
        <InfoTip label="Como esta lista é feita">
          O que mais gente curtiu e salvou nas últimas horas. A lista é a mesma para todo mundo e não olha o que você
          curte nem quem você segue. A fórmula está em <code>params/feed.toml</code>.
        </InfoTip>
      </PageHead>

      <div className="feed">
        {error && <ErrorState message={error} />}
        {!feed && !error && <FeedSkeleton />}
        {feed && feed.items.length === 0 && <Empty>Nada em alta agora.</Empty>}
        {feed?.items.map((post) => <PostCard key={post.id} post={post} showReasons={false} />)}
      </div>
    </div>
  )
}
