import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router'
import { api } from '../api'
import { useApp } from '../app-context'
import { PageHead } from '../components/Layout'
import { EngineChip, ModePicker } from '../components/ModePicker'
import { PostCard } from '../components/PostCard'
import { Composer } from '../components/Composer'
import { Empty, ErrorState, FeedSkeleton } from '../components/States'
import type { FeedResponse, Post } from '../types'

export function HomePage() {
  const { mode, published } = useApp()
  const navigate = useNavigate()
  const [feed, setFeed] = useState<FeedResponse | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let active = true
    setFeed(null)
    setError(null)
    api
      .feed(mode)
      .then((response) => active && setFeed(response))
      .catch((e: Error) => active && setError(e.message))
    return () => {
      active = false
    }
  }, [mode])

  // Texto e foto aparecem aqui mesmo; vídeo e short abrem na aba deles.
  function openWhereItLives(post: Post) {
    if (post.kind === 'video') navigate('/videos')
    if (post.kind === 'short') navigate('/shorts')
  }

  const fresh = published.filter(
    (post) => (post.kind === 'text' || post.kind === 'photo') && !feed?.items.some((item) => item.id === post.id),
  )

  return (
    <div className="page">
      <PageHead brand>
        {feed && <EngineChip engine={feed.engine} />}
        <ModePicker />
      </PageHead>

      <Composer inline onPublished={openWhereItLives} />

      <div className="feed">
        {fresh.map((post) => (
          <PostCard key={`novo-${post.id}`} post={post} showReasons={false} />
        ))}
        {error && <ErrorState message={error} />}
        {!feed && !error && <FeedSkeleton />}
        {feed && feed.items.length === 0 && <Empty>Nada por aqui neste modo.</Empty>}
        {feed?.items.map((post) => <PostCard key={post.id} post={post} />)}
      </div>
    </div>
  )
}
