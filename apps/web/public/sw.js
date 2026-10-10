// Service worker da -rede+social.
//
// Ele existe para o site poder ser instalado como app e abrir mesmo sem rede.
// Por isso guarda só a casca do app: a página inicial, os ícones e os arquivos
// do build. Nunca guarda respostas da API nem fotos e vídeos, porque num
// celular dividido o que uma pessoa viu não pode ficar salvo para a próxima.

const CACHE = 'rede-social-v1'
const SHELL = ['/', '/favicon.svg', '/manifest.webmanifest', '/icons/icon-192.png']

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(CACHE).then((cache) => cache.addAll(SHELL)))
  self.skipWaiting()
})

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((key) => key !== CACHE).map((key) => caches.delete(key))))
      .then(() => self.clients.claim()),
  )
})

self.addEventListener('fetch', (event) => {
  const { request } = event
  const url = new URL(request.url)
  if (request.method !== 'GET' || url.origin !== self.location.origin) return
  if (url.pathname.startsWith('/api/') || url.pathname.startsWith('/uploads/')) return

  // Páginas: sempre da rede; sem rede, a casca guardada.
  if (request.mode === 'navigate') {
    event.respondWith(fetch(request).catch(() => caches.match('/')))
    return
  }

  // Os arquivos do build têm um hash no nome, então nunca mudam e podem ficar
  // guardados até a próxima versão.
  if (url.pathname.startsWith('/assets/')) {
    event.respondWith(
      caches.match(request).then(
        (hit) =>
          hit ||
          fetch(request).then((response) => {
            if (response.ok) {
              const copy = response.clone()
              caches.open(CACHE).then((cache) => cache.put(request, copy))
            }
            return response
          }),
      ),
    )
  }
})
