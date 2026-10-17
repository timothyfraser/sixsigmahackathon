import {defineConfig} from '@playwright/test'
const baseURL=process.env.BIKESMART_TEST_BASE_URL??'http://127.0.0.1:5173'
export default defineConfig({testDir:'./tests',use:{baseURL},webServer:process.env.BIKESMART_TEST_BASE_URL?undefined:{command:'npm run dev -- --port 5173 --strictPort',url:'http://127.0.0.1:5173',reuseExistingServer:true},reporter:'list'})
