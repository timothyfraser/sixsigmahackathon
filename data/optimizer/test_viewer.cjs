// Browser QA for the local, buildless viewer. Uses the existing UI's Playwright.
const path=require('node:path');
const assert=require('node:assert/strict');
const {pathToFileURL}=require('node:url');
const {chromium}=require(path.resolve(__dirname,'../../bike-wise-ui/node_modules/@playwright/test'));

(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'});
 try{
  const page=await browser.newPage({viewport:{width:1440,height:1000}});
  const errors=[];page.on('pageerror',e=>errors.push(e.message));
  // Verify all interactions with network disabled; map tiles are optional.
  await page.route(/^https?:/,route=>route.abort());
  await page.goto(pathToFileURL(path.join(__dirname,'viewer/index.html')).href);
  const data=await page.locator('#optimizer-data').evaluate(el=>JSON.parse(el.textContent));
  const references=data.records.filter(r=>r.reference_time).map(r=>Date.parse(r.reference_time));
  assert.equal(new Set(references).size,1,'All city references must be the same instant');
  let cases=0;
  for(const city of ['jersey_city','milwaukee','tampa']){
   await page.selectOption('#city',city);
   assert.match(await page.locator('#reference').innerText(),
    city==='milwaukee'?/10:55 PM CDT/:/11:55 PM EDT/);
   for(const mode of ['pickup','return']){
    await page.click('#'+mode);
    for(const location of data.locations.filter(l=>l.city===city)){
     await page.selectOption('#location',location.location_id);
     const records=data.records.filter(r=>r.city===city&&r.mode===mode&&r.location_id===location.location_id);
     const eligible=records.filter(r=>r.eligible).sort((a,b)=>a.rank-b.rank);
     const excluded=records.filter(r=>!r.eligible);
     assert.equal(await page.locator('.marker-circle').count(),27);
     assert.equal(await page.locator('.user-marker').count(),1);
     assert.equal(await page.locator('.chart-row').count(),27);
     assert.deepEqual(await page.locator('.dock-card').evaluateAll(els=>els.map(el=>el.dataset.dock)),eligible.map(r=>r.dockID));
     assert.equal(await page.locator('#eligible-tab').getAttribute('aria-selected'),'true');
     await page.click('#excluded-tab');
     assert.equal(await page.locator('.dock-card').count(),excluded.length);
     if(excluded.length) assert.equal(await page.locator('.reason').count(),excluded.length);
     await page.click('#eligible-tab');
     if(eligible.length){
      await page.locator('.dock-card').first().click();
      assert.equal(await page.locator('.dock-card.selected').count(),1);
      assert.equal(await page.locator('.marker-circle.selected').count(),1);
      assert.match(await page.locator('.leaflet-popup-content').last().innerText(),/Projected bikes:/);
     }
     cases++;
    }
   }
  }
  await page.selectOption('#city','milwaukee');await page.click('#return');
  await page.selectOption('#location','MKE-U01');
  assert.match(await page.locator('#reference').innerText(),/10:55 PM CDT/);
  assert.ok(await page.locator('.badge').count()>0);
  await page.locator('.chart-row').nth(2).focus();await page.keyboard.press('Enter');
  assert.equal(await page.locator('.marker-circle.selected').count(),1);
  await page.locator('.leaflet-popup-close-button').last().click();
  await page.screenshot({path:path.join(__dirname,'viewer/preview.png'),fullPage:true});
  await page.setViewportSize({width:390,height:844});
  await page.evaluate(()=>window.dispatchEvent(new Event('resize')));
  assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth));
  assert.ok(await page.locator('#location').isVisible());
  await page.screenshot({path:path.join(__dirname,'viewer/preview_mobile.png'),fullPage:true});
  assert.deepEqual(errors,[]);
  console.log(`PASS: ${cases} city/location/mode combinations; 27 dock markers and occupancy bars each; rankings and exclusions match saved CSV results`);
  console.log('PASS: map/list selection, discount badges, keyboard chart selection, offline operation, mobile layout; zero JavaScript errors');
  console.log('PASS: synchronized reference instant; Milwaukee label is 10:55 PM CDT');
 }finally{await browser.close()}
})().catch(e=>{console.error(e);process.exitCode=1});
