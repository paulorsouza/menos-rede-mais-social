/**
 * Envio que retoma de onde parou (protocolo tus 1.0, o mesmo do backend em
 * /api/envios). O arquivo vai em pedaços; se a conexão cair, o app pergunta
 * ao servidor quantos bytes chegaram e continua dali. O endereço do envio
 * fica guardado no navegador, então dá para retomar até depois de recarregar
 * a página, escolhendo o mesmo arquivo.
 */

const CHUNK = 8 * 1024 * 1024
const MAX_FAILURES = 8
const STORE_KEY = 'rede-social:envios'

export interface UploadHandle {
  /** Resolve com o id do envio quando todos os bytes chegaram. */
  done: Promise<string>
  /** Desiste: para de mandar e apaga o que já chegou no servidor. */
  cancel: () => void
}

export class UploadError extends Error {}

export function startUpload(file: File, onProgress: (fraction: number) => void): UploadHandle {
  let cancelled = false
  let current: XMLHttpRequest | null = null
  let location: string | null = null
  const fingerprint = `${file.name}:${file.size}:${file.lastModified}`

  const done = (async () => {
    location = await resume(fingerprint)
    let offset = location ? await askOffset(location) : null

    if (location === null || offset === null) {
      location = await create(file)
      remember(fingerprint, location)
      offset = 0
    }

    let failures = 0
    while (offset < file.size) {
      if (cancelled) throw new UploadError('Envio cancelado.')
      try {
        offset = await sendChunk(location, file, offset, onProgress, (xhr) => (current = xhr))
        failures = 0
      } catch (error) {
        if (cancelled) throw new UploadError('Envio cancelado.')
        if (error instanceof UploadError) throw error
        failures += 1
        if (failures > MAX_FAILURES) throw new UploadError('A conexão caiu muitas vezes. Tente de novo mais tarde.')
        // Espera um pouco mais a cada falha e pergunta onde parou.
        await sleep(Math.min(30_000, 1000 * 2 ** (failures - 1)))
        offset = (await askOffset(location).catch(() => null)) ?? offset
      }
    }

    onProgress(1)
    forget(fingerprint)
    return location.split('/').pop()!
  })()

  return {
    done,
    cancel() {
      cancelled = true
      current?.abort()
      forget(fingerprint)
      if (location) fetch(location, { method: 'DELETE', headers: { 'Tus-Resumable': '1.0.0' } }).catch(() => undefined)
    },
  }
}

async function create(file: File): Promise<string> {
  const response = await fetch('/api/envios', {
    method: 'POST',
    credentials: 'same-origin',
    headers: {
      'Tus-Resumable': '1.0.0',
      'Upload-Length': String(file.size),
      'Upload-Metadata': `filename ${base64(file.name)},filetype ${base64(file.type)}`,
    },
  })
  if (!response.ok) {
    const body = await response.json().catch(() => null)
    throw new UploadError(body?.error ?? 'Não foi possível começar o envio.')
  }
  return response.headers.get('Location')!
}

/** Quantos bytes já chegaram, ou null se o envio não existe mais. */
async function askOffset(location: string): Promise<number | null> {
  const response = await fetch(location, { method: 'HEAD', headers: { 'Tus-Resumable': '1.0.0' }, cache: 'no-store' })
  if (response.status === 404) return null
  if (!response.ok) throw new Error(`HEAD ${response.status}`)
  return Number(response.headers.get('Upload-Offset'))
}

// XMLHttpRequest, e não fetch, porque só ele conta os bytes enquanto sobem:
// numa internet lenta, um pedaço leva minutos e a barra precisa andar.
function sendChunk(
  location: string,
  file: File,
  offset: number,
  onProgress: (fraction: number) => void,
  track: (xhr: XMLHttpRequest) => void,
): Promise<number> {
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest()
    track(xhr)
    xhr.open('PATCH', location)
    xhr.setRequestHeader('Tus-Resumable', '1.0.0')
    xhr.setRequestHeader('Upload-Offset', String(offset))
    xhr.setRequestHeader('Content-Type', 'application/offset+octet-stream')
    xhr.upload.onprogress = (event) => onProgress((offset + event.loaded) / file.size)
    xhr.onload = () => {
      if (xhr.status === 204) resolve(Number(xhr.getResponseHeader('Upload-Offset')))
      else if (xhr.status === 409 || xhr.status >= 500 || xhr.status === 423) reject(new Error(`PATCH ${xhr.status}`))
      else reject(new UploadError(messageOf(xhr) ?? 'O servidor recusou o arquivo.'))
    }
    xhr.onerror = () => reject(new Error('rede'))
    xhr.onabort = () => reject(new Error('cancelado'))
    xhr.send(file.slice(offset, offset + CHUNK))
  })
}

function messageOf(xhr: XMLHttpRequest): string | undefined {
  try {
    return JSON.parse(xhr.responseText).error
  } catch {
    return undefined
  }
}

// Upload-Metadata vai em base64; o nome do arquivo pode ter acento.
function base64(text: string): string {
  const bytes = new TextEncoder().encode(text)
  let binary = ''
  bytes.forEach((byte) => (binary += String.fromCharCode(byte)))
  return btoa(binary)
}

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms))

function readStore(): Record<string, string> {
  try {
    return JSON.parse(localStorage.getItem(STORE_KEY) ?? '{}')
  } catch {
    return {}
  }
}

function writeStore(store: Record<string, string>) {
  try {
    localStorage.setItem(STORE_KEY, JSON.stringify(store))
  } catch {
    // Sem armazenamento no navegador: o envio ainda retoma enquanto a aba estiver aberta.
  }
}

async function resume(fingerprint: string): Promise<string | null> {
  return readStore()[fingerprint] ?? null
}

function remember(fingerprint: string, location: string) {
  writeStore({ ...readStore(), [fingerprint]: location })
}

function forget(fingerprint: string) {
  const store = readStore()
  delete store[fingerprint]
  writeStore(store)
}
