import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// base './' makes every asset path relative, so the built dist/ works at any
// URL - including a Posit Connect content path like /content/<guid>/.
export default defineConfig({
  plugins: [react()],
  base: './',
  test: {
    environment: 'node',
    include: ['src/**/*.test.js'],
  },
})
