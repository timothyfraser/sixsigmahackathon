import {test,expect} from '@playwright/test'
import {readFileSync} from 'node:fs'
import {gunzipSync} from 'node:zlib'
const data=(city,file)=>JSON.parse(gunzipSync(readFileSync(new URL(`../server/data/fleet/${city}/${file}.json.gz`,import.meta.url))))
async function login(page){
 await page.goto('/');await page.getByRole('button',{name:'maintenance login here',exact:true}).click()
 await page.getByLabel('Email address',{exact:true}).fill('maintenance@cornell.edu')
 if(!process.env.MAINTENANCE_TEST_PASSWORD)throw new Error('Set MAINTENANCE_TEST_PASSWORD for browser tests.')
 await page.getByLabel('Password',{exact:true}).fill(process.env.MAINTENANCE_TEST_PASSWORD)
 await page.getByRole('button',{name:'Sign in',exact:true}).click()
 await expect(page.getByRole('region',{name:'Fleet monitor',exact:true})).toBeVisible()
}
test('fleet_viz is the first maintenance view and its data requires login',async({page})=>{
 await page.goto('/')
 expect((await page.request.get('/api/maintenance/fleet/network?city=jersey')).status()).toBe(401)
 expect((await page.request.get('/api/maintenance/fleet/day?city=jersey&date=2026-09-16')).status()).toBe(401)
 expect((await page.request.get('/server/data/fleet/jersey_city/network.json.gz')).status()).not.toBe(200)
 await login(page)
 await expect(page.getByRole('button',{name:'Fleet monitor',exact:true})).toHaveAttribute('aria-pressed','true')
 await expect(page.getByRole('region',{name:'Dispatch priorities',exact:true})).toHaveCount(0)
 await expect(page.locator('[data-fleet-station]')).toHaveCount(27)
 await expect(page.getByLabel('All 405 bikes',{exact:true})).toBeChecked()
 const network=await page.request.get('/api/maintenance/fleet/network?city=jersey')
 expect((await network.json()).source).toBe('demo/fleet_viz/app.R')
 await page.screenshot({path:'test-results/fleet-landing.png',fullPage:true})
})
test('playback, outage highlights and station inspector match recorded snapshots',async({page})=>{
 const network=data('jersey_city','network'),day=data('jersey_city',network.default_date)
 await login(page)
 await page.getByRole('button',{name:'Next snapshot',exact:true}).click()
 const step=Number(await page.locator('.fleet-monitor').getAttribute('data-step'))
 await expect(page.getByTestId('fleet-in-transit')).toHaveText(String(day.bike_docks[step-1].filter(d=>d===-1).length))
 await expect(page.getByTestId('fleet-empty')).toHaveText(String(day.dock_mat[step-1].filter(d=>d===0).length))
 await page.getByRole('button',{name:/Stations empty/}).click()
 await expect(page.locator('.fleet-outage-highlight')).toHaveCount(day.dock_mat[step-1].filter(d=>d===0).length)
 await page.getByRole('button',{name:/Stations full/}).click()
 await expect(page.locator('.fleet-outage-highlight')).toHaveCount(day.dock_mat[step-1].filter(d=>d===30).length)
 await expect(page.getByRole('button',{name:/Stations empty/})).toHaveAttribute('aria-pressed','false')
 await page.locator('[data-fleet-station]').first().dispatchEvent('click')
 await expect(page.getByLabel('Fleet station',{exact:true})).toHaveValue('0')
 await expect(page.getByTestId('fleet-station-count')).toHaveText(`${day.dock_mat[step-1][0]} / 30`)
 await expect(page.getByRole('img',{name:'Station inventory across the selected day'})).toBeVisible()
 await page.getByRole('button',{name:'Play',exact:true}).click()
 await expect.poll(async()=>Number(await page.locator('.fleet-monitor').getAttribute('data-step'))).toBeGreaterThan(step)
 await page.getByRole('button',{name:'Pause',exact:true}).click()
 const stopped=await page.locator('.fleet-monitor').getAttribute('data-step')
 await page.getByRole('button',{name:'Previous snapshot',exact:true}).click()
 await expect(page.locator('.fleet-monitor')).toHaveAttribute('data-step',String(Number(stopped)-1))
 await page.screenshot({path:'test-results/fleet-inspector.png',fullPage:true})
})
test('single-bike paths, dates and all city networks work without runtime errors',async({page})=>{
 const errors=[];page.on('pageerror',e=>errors.push(e.message));await login(page)
 for(const [id,city] of [['jersey','jersey_city'],['milwaukee','milwaukee'],['tampa','tampa']]){
  await page.getByRole('button',{name:city==='jersey_city'?'Jersey City':city==='tampa'?'Tampa':'Milwaukee',exact:true}).click()
  await expect(page.getByLabel('Supported network')).toHaveValue(id)
  const network=data(city,'network'),day=data(city,network.default_date)
  expect(network.route_source).toContain('OpenStreetMap')
  expect(network.routes.some(route=>route.n>10)).toBe(true)
  expect(network.routes.every(route=>route.cumulative.length===route.n)).toBe(true)
  await expect(page.getByLabel('Replay date',{exact:true})).toHaveValue(network.default_date)
  await expect(page.locator('[data-fleet-station]')).toHaveCount(27)
  await page.getByLabel('Single bike journey',{exact:true}).check()
  const step=Number(await page.locator('.fleet-monitor').getAttribute('data-step'))
  const index=day.bike_docks[step-1].findIndex(dock=>dock>=0)
  await page.getByLabel('Bike to track',{exact:true}).selectOption(String(index))
  await expect(page.locator('.fleet-bike-status')).toContainText(network.bike_ids[index])
  await expect(page.locator('.fleet-bike-status')).toContainText(network.stations[day.bike_docks[step-1][index]].dockID)
  await page.getByLabel('Display path history',{exact:true}).uncheck()
  await page.getByRole('button',{name:'Next day',exact:true}).click()
  const next=network.dates[network.dates.findIndex(d=>d.date===network.default_date)+1].date
  await expect(page.getByLabel('Replay date',{exact:true})).toHaveValue(next)
  await expect(page.locator('.fleet-trails-canvas')).toBeVisible()
  await page.getByRole('button',{name:'Previous day',exact:true}).click()
  await expect(page.getByLabel('Replay date',{exact:true})).toHaveValue(network.default_date)
 }
 expect(errors).toEqual([])
})
test('fleet monitor is usable on a phone and existing maintenance sections remain available',async({page})=>{
 await page.setViewportSize({width:390,height:844});await login(page)
 await expect(page.locator('.fleet-map-panel')).toBeVisible()
 await page.getByRole('button',{name:'Station inspector',exact:true}).click()
 await page.getByLabel('Fleet station',{exact:true}).selectOption('5')
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true)
 await page.screenshot({path:'test-results/fleet-mobile.png',fullPage:true})
 await page.getByRole('button',{name:'Dispatch priorities',exact:true}).click()
 await expect(page.getByRole('heading',{name:'Where to go first'})).toBeVisible()
 await page.getByRole('button',{name:'Fleet monitor',exact:true}).click()
 await expect(page.locator('[data-fleet-station]')).toHaveCount(27)
})

test('bike paths paint above tiles and bike heads move smoothly between snapshot ticks',async({page})=>{
 await login(page)
 const canvas=page.locator('.fleet-trails-canvas')
 await expect.poll(async()=>Number(await canvas.getAttribute('data-active-heads'))).toBeGreaterThan(0)
 // Checking for a canvas alone misses regressions where the map covers its ink.
 const visibleInk=await canvas.evaluate(node=>{
  const ctx=node.getContext('2d'),pixels=ctx.getImageData(0,0,node.width,node.height).data
  let painted=0;for(let i=3;i<pixels.length;i+=4)if(pixels[i])painted++
  const head=JSON.parse(node.dataset.firstHead)
  window.scrollBy(0,node.getBoundingClientRect().top+head.y-innerHeight/2)
  const rect=node.getBoundingClientRect()
  node.style.pointerEvents='auto'
  const top=document.elementFromPoint(rect.left+head.x,rect.top+head.y)
  node.style.pointerEvents='none'
  return{painted,onTop:top===node}
 })
 expect(visibleInk.painted).toBeGreaterThan(100)
 expect(visibleInk.onTop).toBe(true)
 await page.getByLabel('Replay speed',{exact:true}).selectOption('1000')
 await page.getByRole('button',{name:'Play',exact:true}).click()
 // Collect adjacent display frames within a single snapshot interval.
 const frames=await canvas.evaluate(node=>new Promise(resolve=>{
  const samples=[]
  function sample(){samples.push({step:Number(node.dataset.step),head:node.dataset.firstHead});if(samples.length<8)requestAnimationFrame(sample);else resolve(samples)}
  requestAnimationFrame(sample)
 }))
 expect(frames.some((value,i)=>i&&value.head!==frames[i-1].head)).toBe(true)
 expect(frames.some(value=>value.step%1>0)).toBe(true)
 for(let i=1;i<frames.length;i++)expect(Math.abs(frames[i].step-frames[i-1].step)).toBeLessThan(.5)
 await page.getByRole('button',{name:'Pause',exact:true}).click()
 const paused=await canvas.getAttribute('data-step')
 await page.waitForTimeout(150)
 await expect(canvas).toHaveAttribute('data-step',paused)
 await page.screenshot({path:'test-results/fleet-visible-bike-paths.png',fullPage:true})
})
