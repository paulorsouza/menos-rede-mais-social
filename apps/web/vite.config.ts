import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    // Em desenvolvimento, as chamadas para /api vão para o Phoenix.
    proxy: { '/api': 'http://localhost:4000' },
  },
})
