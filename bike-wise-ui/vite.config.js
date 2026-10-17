import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import {maintenanceApiPlugin} from './server/api.mjs'
export default defineConfig({plugins:[react(),maintenanceApiPlugin()],base:'./',server:{fs:{deny:['.env','.env.*','*.{crt,pem}','**/.git/**','**/server/**']}},test:{environment:'jsdom',include:['src/**/*.test.{js,jsx}'],setupFiles:['./src/testSetup.js']}})
