import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// No Docker, o backend se chama "backend"; rodando direto na máquina, é localhost.
const apiUrl = process.env.API_URL ?? 'http://localhost:4000'

export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      '/api': apiUrl,
      '/uploads': apiUrl,
    },
  },
})
