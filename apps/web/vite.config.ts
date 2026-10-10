import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// No Docker, o backend se chama "backend"; rodando direto na máquina, é localhost.
const apiUrl = process.env.API_URL ?? 'http://localhost:4000'
// Fotos e vídeos: no Docker vêm da borda (o papel da CDN); fora dele, o
// próprio backend serve a pasta local.
const mediaUrl = process.env.MEDIA_URL ?? apiUrl
// Lives (MediaMTX): HLS para quem assiste e WHIP para quem transmite. O HLS
// fica em /ao-vivo porque o MediaMTX redireciona para esse caminho; por isso a
// tela de fazer live é /transmitir.
const liveUrl = process.env.LIVE_URL ?? 'http://localhost'

export default defineConfig({
  plugins: [react()],
  server: {
    // No Docker com a pasta vinda do Windows, o aviso de arquivo mudado nem
    // sempre chega ao contêiner; aí o Vite confere os arquivos de tempos em tempos.
    watch: process.env.VITE_POLLING ? { usePolling: true, interval: 500 } : undefined,
    proxy: {
      '/api': apiUrl,
      '/media': mediaUrl,
      '/ao-vivo': `${liveUrl}:8888`,
      '/whip': { target: `${liveUrl}:8889`, rewrite: (path) => path.replace(/^\/whip/, '') },
    },
  },
})
