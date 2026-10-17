import {test,expect} from '@playwright/test'
import {readFileSync} from 'node:fs'

const password=()=>{
 const value=process.env.MAINTENANCE_TEST_PASSWORD
 if(!value)throw new Error('Set MAINTENANCE_TEST_PASSWORD to the demo login password before running maintenance browser tests.')
 return value
}
async function login(page){
 await page.goto('/')
 await page.getByRole('button',{name:'maintenance login here',exact:true}).click()
 await page.getByLabel('Email address',{exact:true}).fill('maintenance@cornell.edu')
 await page.getByLabel('Password',{exact:true}).fill(password())
 await page.getByRole('button',{name:'Sign in',exact:true}).click()
 await expect(page.getByRole('navigation',{name:'Maintenance sections'})).toBeVisible()
}

test('maintenance login rejects invalid credentials and protects report data',async({page})=>{
 await page.goto('/')
 expect((await page.request.get('/api/maintenance/report?city=jersey')).status()).toBe(401)
 expect((await page.request.get('/server/data/maintenance.json')).status()).not.toBe(200)
 expect((await page.request.post('/api/maintenance/reliability',{data:{rates:{flat_tire:0.02},projected:20}})).status()).toBe(401)
 await page.getByRole('button',{name:'maintenance login here',exact:true}).click()
 await expect(page.getByRole('heading',{name:'Maintenance sign in'})).toBeVisible()
 await page.getByLabel('Email address',{exact:true}).fill('maintenance@cornell.edu')
 await page.getByLabel('Password',{exact:true}).fill('incorrect-demo-input')
 await page.getByRole('button',{name:'Sign in',exact:true}).click()
 await expect(page.getByRole('alert')).toContainText('incorrect')
 await expect(page.getByRole('navigation',{name:'Maintenance sections'})).toHaveCount(0)
 await page.getByLabel('Password',{exact:true}).fill(password())
 await page.getByRole('button',{name:'Sign in',exact:true}).click()
 await expect(page.getByRole('navigation',{name:'Maintenance sections'})).toBeVisible()
 const cookies=await page.context().cookies()
 expect(cookies.find(c=>c.name==='maintenance_session')).toMatchObject({httpOnly:true,sameSite:'Strict'})
 await page.getByRole('button',{name:'Sign out',exact:true}).click()
 expect((await page.request.get('/api/maintenance/report?city=jersey')).status()).toBe(401)
 await page.getByRole('button',{name:'maintenance login here',exact:true}).click()
 await expect(page.getByRole('heading',{name:'Maintenance sign in'})).toBeVisible()
})

test('maintenance report matches R outputs for each city and supports dispatch inspection',async({page})=>{
 const reports=JSON.parse(readFileSync(new URL('../server/data/maintenance.json',import.meta.url),'utf8'))
 const errors=[];page.on('pageerror',e=>errors.push(e.message))
 await login(page)
 for(const [id,city] of [['jersey','jersey_city'],['milwaukee','milwaukee'],['tampa','tampa']]){
  await page.getByLabel('Supported network').selectOption(id)
  const report=reports[city]
  await page.getByRole('button',{name:'Dispatch priorities',exact:true}).click()
  await expect(page.locator('.fleet-metrics>div').nth(0).locator('strong')).toHaveText(String(report.fleet_size))
  await expect(page.locator('.fleet-metrics>div').nth(1).locator('strong')).toHaveText(String(report.service_due.length))
  await page.getByRole('button',{name:'Dispatch priorities',exact:true}).click()
  const first=report.stations[0]
  await expect(page.locator('.maintenance-dispatch tbody tr').first()).toContainText(first.DOCID)
  await expect(page.locator('.maintenance-dispatch tbody tr')).toHaveCount(report.stations.length)
  await page.getByRole('button',{name:'View bikes',exact:true}).first().click()
  await expect(page.getByLabel('Service station filter')).toHaveValue(first.DOCID)
  await expect(page.locator('.maintenance-panel tbody tr')).toHaveCount(report.service_due.filter(r=>r.current_dock===first.DOCID).length)
  await page.getByRole('button',{name:'In-transit alerts',exact:true}).click()
  await expect(page.locator('.maintenance-panel tbody tr')).toHaveCount(report.stuck_alerts.length)
  await page.getByRole('checkbox',{name:'Show all currently in-transit bikes'}).check()
  await expect(page.locator('.maintenance-panel tbody tr')).toHaveCount(report.transit.length)
  await page.getByRole('button',{name:'Quality chart',exact:true}).click()
  await expect(page.getByRole('img',{name:/P chart with daily shares/})).toBeVisible()
  await expect(page.locator('.maintenance-panel tbody tr')).toHaveCount(report.chart.length)
  const row=report.chart[0]
  await expect(page.locator('.maintenance-panel tbody tr').first()).toContainText(`${row.d} / ${row.n}`)
 }
 expect(errors).toEqual([])
 await page.screenshot({path:'test-results/maintenance-quality.png',fullPage:true})
})

test('reliability uses package known answer and server rejects invalid rates',async({page})=>{
 await login(page)
 await page.getByRole('button',{name:'Fleet reliability',exact:true}).click()
 await page.getByLabel('Flat tire (%)',{exact:true}).fill('2')
 await page.getByLabel('Battery fault (%)',{exact:true}).fill('5')
 await page.getByLabel('Chain / brake fault (%)',{exact:true}).fill('0')
 await page.getByLabel('Projected bikes',{exact:true}).fill('20')
 await page.getByRole('button',{name:'Calculate usable fleet',exact:true}).click()
 await expect(page.locator('.reliability-result')).toContainText('93.1%')
 await expect(page.locator('.reliability-result')).toContainText('18.62')
 expect((await page.request.post('/api/maintenance/reliability',{data:{rates:{tire:2},projected:20}})).status()).toBe(400)
 const zero=await page.request.post('/api/maintenance/reliability',{data:{rates:{tire:1},projected:20}})
 expect(zero.status()).toBe(200);expect((await zero.json()).usable_bikes).toBe(0)
 const forgery=await page.request.post('/api/maintenance/logout',{headers:{Origin:'https://invalid.example'}})
 expect(forgery.status()).toBe(403)
 await page.screenshot({path:'test-results/maintenance-reliability.png',fullPage:true})
})

test('rider selection survives maintenance login and both views fit mobile',async({page})=>{
 await page.setViewportSize({width:390,height:844});await page.goto('/')
 await page.getByRole('button',{name:'Rent a Bike',exact:true}).click()
 await page.getByLabel('Optimizer location').selectOption('JC-U05')
 await page.getByRole('button',{name:'Find pickup docks',exact:true}).click()
 const card=page.locator('.optimizer-card').nth(2),dock=await card.getAttribute('data-dock');await card.click()
 await page.getByRole('button',{name:'maintenance login here',exact:true}).click()
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true)
 await page.getByLabel('Email address',{exact:true}).fill('maintenance@cornell.edu')
 await page.getByLabel('Password',{exact:true}).fill(password())
 await page.getByRole('button',{name:'Sign in',exact:true}).click()
 await expect(page.getByRole('navigation',{name:'Maintenance sections'})).toBeVisible()
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true)
 await page.screenshot({path:'test-results/maintenance-mobile.png',fullPage:true})
 await page.locator('header').getByRole('button',{name:'Back to rider site',exact:true}).click()
 await expect(page.locator('.optimizer-card.selected')).toHaveAttribute('data-dock',dock)
 await expect(page.getByRole('button',{name:'Choose this pickup station'})).toBeEnabled()
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true)
})
