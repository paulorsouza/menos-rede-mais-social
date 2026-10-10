/**
 * Transmissão pelo navegador, no protocolo WHIP (WebRTC). A câmera vai
 * direto para o servidor de lives (infra/ao-vivo); o backend só autoriza a
 * chave. O vídeo sai em H.264 sempre que o navegador tem, porque é o formato
 * que a gravação e o HLS de quem assiste tocam em qualquer aparelho.
 */

export interface Broadcast {
  stop: () => void
}

export async function broadcast(whipUrl: string, key: string, stream: MediaStream): Promise<Broadcast> {
  const pc = new RTCPeerConnection()
  for (const track of stream.getTracks()) pc.addTransceiver(track, { direction: 'sendonly', streams: [stream] })

  const video = pc.getTransceivers().find((transceiver) => transceiver.sender.track?.kind === 'video')
  const codecs = RTCRtpSender.getCapabilities('video')?.codecs ?? []
  const h264 = codecs.filter((codec) => codec.mimeType === 'video/H264')
  if (video && h264.length > 0) video.setCodecPreferences([...h264, ...codecs.filter((codec) => codec.mimeType !== 'video/H264')])

  await pc.setLocalDescription(await pc.createOffer())
  await iceGathered(pc)

  const response = await fetch(whipUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/sdp', Authorization: `Bearer ${key}` },
    body: pc.localDescription!.sdp,
  })
  if (!response.ok) {
    pc.close()
    throw new Error(response.status === 401 ? 'A chave da live não foi aceita.' : 'O servidor de lives não respondeu.')
  }

  await pc.setRemoteDescription({ type: 'answer', sdp: await response.text() })

  // O endereço da sessão vem relativo ao servidor de lives, que o app
  // alcança por /whip.
  const session = response.headers.get('Location')
  const sessionUrl = session && (session.startsWith('/whip') ? session : `/whip${session}`)

  return {
    stop() {
      pc.close()
      if (sessionUrl) fetch(sessionUrl, { method: 'DELETE', headers: { Authorization: `Bearer ${key}` } }).catch(() => undefined)
    },
  }
}

// Sem troca de candidatos depois da oferta: espera juntar todos (ou 2 s).
function iceGathered(pc: RTCPeerConnection): Promise<void> {
  if (pc.iceGatheringState === 'complete') return Promise.resolve()
  return new Promise((resolve) => {
    const done = () => {
      pc.removeEventListener('icegatheringstatechange', check)
      resolve()
    }
    const check = () => pc.iceGatheringState === 'complete' && done()
    pc.addEventListener('icegatheringstatechange', check)
    setTimeout(done, 2000)
  })
}
