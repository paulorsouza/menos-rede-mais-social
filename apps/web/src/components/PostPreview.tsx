import { timeAgo } from '../format'
import type { Post } from '../types'
import { Avatar, Verified } from './Avatar'

/**
 * O post em tamanho pequeno, sem curtir nem salvar. Serve para a moderação e
 * para os avisos, onde o post pode estar fora do ar.
 */
export function PostPreview({ post }: { post: Post }) {
  return (
    <div className="preview">
      <header className="preview-head">
        <Avatar nickname={post.author.nickname} size={24} />
        <strong>
          {post.author.nickname}
          {post.author.verified && <Verified size={12} />}
        </strong>
        <span className="post-time">{timeAgo(post.created_at)}</span>
      </header>
      {post.body && <p className="preview-text">{post.body}</p>}
      {post.kind === 'photo' && post.media_url && <img className="preview-media" src={post.media_url} alt={post.alt_text ?? post.body ?? 'Foto'} />}
      {(post.kind === 'video' || post.kind === 'short') && post.media_url && (
        <video className="preview-media" src={post.media_url} controls preload="metadata" aria-label={post.body ?? 'Vídeo'} />
      )}
    </div>
  )
}
