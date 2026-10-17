import {test,expect} from '@playwright/test'
import data from '../src/data/optimizer.json' with {type:'json'}

test('all 60 inputs list the R top five and show five green plus other yellow markers',async({page})=>{
 const errors=[];page.on('pageerror',e=>errors.push(e.message));await page.goto('/')
 for(const [network,city] of [['jersey','jersey_city'],['milwaukee','milwaukee'],['tampa','tampa']]){
  await page.getByLabel('Supported network').selectOption(network)
  for(const mode of ['pickup','return']){
   await page.getByRole('button',{name:mode==='pickup'?'Rent a Bike':'Return a Bike',exact:true}).click()
   for(const location of data.locations.filter(l=>l.city===city)){
    await page.getByLabel('Optimizer location').selectOption(location.location_id)
    await page.getByRole('button',{name:mode==='pickup'?'Find pickup docks':'Find return docks',exact:true}).click()
    const rows=data.records.filter(r=>r.city===city&&r.mode===mode&&r.location_id===location.location_id)
    const eligible=rows.filter(r=>r.eligible).sort((a,b)=>a.rank-b.rank).slice(0,5),excluded=rows.filter(r=>!r.eligible)
    await expect(page.locator('.optimizer-card')).toHaveCount(eligible.length)
    await expect(page.locator('.occupancy-row')).toHaveCount(eligible.length)
    await expect(page.locator('.optimizer-map-wrap path[data-dock]')).toHaveCount(27)
    await expect(page.locator('.optimizer-map-wrap path[data-recommended="true"]')).toHaveCount(eligible.length)
    expect(await page.locator('.optimizer-card').evaluateAll(els=>els.map(el=>el.dataset.dock))).toEqual(eligible.map(r=>r.dockID))
    for(const [index,row] of eligible.entries()){
     const card=page.locator('.optimizer-card').nth(index)
     await expect(card).toContainText(row.distance_miles.toFixed(2)+' mi')
     await expect(card).toContainText((mode==='pickup'?row.projected_bikes:row.projected_spaces).toFixed(1))
     if(mode==='return')await expect(card.locator('.discount-badge')).toHaveText(row.discount_percent?`${row.discount_percent}% demo discount`:'No discount')
    }
    await page.getByRole('button',{name:`Excluded (${excluded.length})`,exact:true}).click()
    await expect(page.locator('.optimizer-card')).toHaveCount(excluded.length)
    await expect(page.locator('.occupancy-row')).toHaveCount(excluded.length)
    await expect(page.locator('.optimizer-map-wrap path[data-dock]')).toHaveCount(27)
    for(const row of excluded)await expect(page.locator('.optimizer-card').filter({hasText:row.dockID})).toContainText('Fewer than 1 projected')
    await page.getByRole('button',{name:'Back',exact:true}).click()
   }
  }
 }
 expect(errors).toEqual([])
})

test('selection synchronizes across map list chart; excluded dock cannot continue',async({page})=>{
 await page.goto('/');await page.getByRole('button',{name:'Return a Bike',exact:true}).click()
 await page.getByRole('button',{name:'Find return docks',exact:true}).click()
 await expect(page.getByRole('button',{name:'Choose this return dock'})).toBeDisabled()
 const card=page.locator('.optimizer-card').nth(2),name=await card.getAttribute('data-dock');await card.click()
 await expect(page.locator('.occupancy-row.selected')).toHaveAttribute('aria-label',new RegExp(`^${name}:`))
 await expect(page.locator('.optimizer-selected')).toContainText(name)
 const firstDock=await page.locator('.optimizer-card').first().getAttribute('data-dock')
 await page.locator('.optimizer-map-wrap').locator(`path[data-dock="${firstDock}"]`).dispatchEvent('click')
 await expect(page.locator('.optimizer-card.selected')).toHaveAttribute('data-dock',firstDock)
 await page.locator('.occupancy-row').nth(1).focus();await page.keyboard.press('Enter')
 await expect(page.locator('.optimizer-card').nth(1)).toHaveAttribute('aria-pressed','true')
 await page.getByRole('button',{name:/Excluded \(/}).click()
 await page.locator('.optimizer-card').first().click()
 await expect(page.getByRole('button',{name:'Choose this return dock'})).toBeDisabled()
 await expect(page.locator('.time-error')).toContainText('excluded')
 await page.getByRole('button',{name:/Eligible \(/}).click()
 await page.locator('.optimizer-card').first().click()
 await expect(page.getByRole('button',{name:'Choose this return dock'})).toBeEnabled()
 await page.screenshot({path:'test-results/top-five-desktop.png',fullPage:true})
})
