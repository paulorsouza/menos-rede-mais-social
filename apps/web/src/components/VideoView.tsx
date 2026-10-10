import { useCallback, useEffect, useRef } from 'react'
import type { Ref, VideoHTMLAttributes } from 'react'
import type Hls from 'hls.js'
import { useApp } from '../app-context'
import type { Post } from '../types'

// O mesmo teto de params/video.toml ([data_saver] max_short_side).
const DATA_SAVER_SHORT_SIDE = 360

interface Props extends Omit<VideoHTMLAttributes<HTMLVideoElement>, 'src' | 'poster'> {
  post: Post
  /** Toca quando true e pausa quando false. Sem ele, quem manda são os controles. */
  playing?: boolean
  /** Liga a legenda automática de saída (nos shorts, que começam sem som). */
  captionsOn?: boolean
  /**
   * Altura da legenda, em porcentagem a partir do topo. Nos shorts, a parte
   * de baixo da tela tem o nome de quem publicou e a barra de navegação.
   */
  captionsAt?: number
  ref?: Ref<HTMLVideoElement>
}

/**
 * O player de vídeo da rede. O vídeo chega em HLS: vários degraus de
 * qualidade, e o player troca de degrau conforme a internet aguenta. Quem
 * troca é o hls.js, baixado só quando algum vídeo aparece na tela; onde ele
 * não roda, o navegador toca o HLS sozinho.
 *
 * Nada do vídeo é baixado antes de tocar: até lá, aparece só a capa. No
 * modo econômico, o player não passa do degrau de 360.
 */
export function VideoView({ post, playing, captionsOn = false, captionsAt, ref, ...props }: Props) {
  const { dataSaver } = useApp()
  const video = useRef<HTMLVideoElement | null>(null)
  const track = useRef<HTMLTrackElement>(null)
  // O hls.js chega depois do primeiro play: aí ele confere se ainda é para tocar.
  const wantsPlay = useRef(playing)
  wantsPlay.current = playing

  const setRef = useCallback(
    (element: HTMLVideoElement | null) => {
      video.current = element
      if (typeof ref === 'function') ref(element)
      else if (ref) ref.current = element
    },
    [ref],
  )

  useEffect(() => {
    const element = video.current
    const src = post.media_url
    if (!element || !src) return

    // Vídeo que não é HLS (arquivo antigo, por exemplo) toca direto.
    if (!src.endsWith('.m3u8')) {
      element.src = src
      return () => detach(element)
    }

    let hls: Hls | null = null
    let cancelled = false

    // O hls.js vem primeiro mesmo onde o navegador toca HLS sozinho (Chrome
    // novo, Safari): só com ele dá para segurar a qualidade no modo
    // econômico. O HLS do navegador fica para quem não roda o hls.js. É a
    // versão "light": a legenda usa a trilha do próprio navegador e não há
    // DRM, então o resto do hls.js seria peso à toa.
    import('hls.js/light').then(({ default: HlsClass }) => {
      if (cancelled) return
      if (!HlsClass.isSupported()) {
        element.src = src
        if (wantsPlay.current) element.play().catch(() => undefined)
        return
      }
      const instance = new HlsClass({
        // Só começa a baixar quando a pessoa (ou o feed de shorts) dá play.
        autoStartLoad: false,
        capLevelToPlayerSize: !dataSaver,
        startLevel: dataSaver ? 0 : -1,
        maxBufferLength: dataSaver ? 10 : 30,
      })
      hls = instance

      // No modo econômico, o teto é o degrau de 360. (O ajuste pelo tamanho
      // do player fica desligado nesse modo, porque ele reescreve o teto.)
      instance.on(HlsClass.Events.MANIFEST_PARSED, (_event, data) => {
        if (!dataSaver) return
        const allowed = data.levels.filter((level) => Math.min(level.width, level.height) <= DATA_SAVER_SHORT_SIDE)
        instance.autoLevelCapping = Math.max(0, allowed.length - 1)
      })

      instance.loadSource(src)
      instance.attachMedia(element)

      // O play pode ter vindo antes do hls.js chegar (o aviso já passou):
      // aí começa a baixar agora. Senão, espera o play.
      const start = () => instance.startLoad(-1)
      if (wantsPlay.current || !element.paused) {
        start()
        element.play().catch(() => undefined)
      } else {
        element.addEventListener('play', start, { once: true })
      }
    })

    return () => {
      cancelled = true
      hls?.destroy()
      detach(element)
    }
  }, [post.media_url, dataSaver])

  // Reposiciona a legenda quando o arquivo dela termina de chegar. (O
  // onLoad do React não vale para <track>, por isso o evento é ouvido aqui.)
  useEffect(() => {
    const element = track.current
    if (!element || captionsAt === undefined) return
    const place = () => placeCues(element.track, captionsAt)
    if (element.readyState === HTMLTrackElement.LOADED) place()
    element.addEventListener('load', place)
    return () => element.removeEventListener('load', place)
  }, [captionsAt, post.captions_url])

  useEffect(() => {
    const element = video.current
    if (!element || playing === undefined) return
    if (playing) element.play().catch(() => undefined)
    else element.pause()
  }, [playing])

  return (
    <video ref={setRef} poster={post.poster_url ?? undefined} preload="none" playsInline {...props}>
      {post.captions_url && (
        <track
          ref={track}
          kind="captions"
          src={post.captions_url}
          srcLang="pt"
          label="Português (automática)"
          default={captionsOn}
        />
      )}
    </video>
  )
}

function placeCues(track: TextTrack, percent: number) {
  // O navegador só redesenha a legenda na nova altura se a trilha for
  // desligada e ligada de novo.
  const mode = track.mode
  track.mode = 'hidden'
  for (const cue of Array.from(track.cues ?? [])) {
    if (cue instanceof VTTCue) {
      cue.snapToLines = false
      cue.line = percent
    }
  }
  track.mode = mode
}

function detach(element: HTMLVideoElement) {
  element.pause()
  element.removeAttribute('src')
  element.load()
}
