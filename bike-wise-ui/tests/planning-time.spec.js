import {test,expect} from '@playwright/test'

// The recorded R export has one reference instant; browser time must not change it.
test.use({timezoneId:'Asia/Tokyo'})
test('all modes retain recorded reference time in the selected city timezone',async({page})=>{
  await page.clock.setFixedTime(new Date('2027-01-20T10:00:00Z'))
  await page.goto('/')
  for(const [network,time,zone] of [['jersey','11:55 PM EDT','America/New_York'],['milwaukee','10:55 PM CDT','America/Chicago'],['tampa','11:55 PM EDT','America/New_York']]){
    await page.getByLabel('Supported network').selectOption(network)
    for(const mode of ['Rent a Bike','Return a Bike']){
      await page.getByRole('button',{name:mode,exact:true}).click()
      await expect(page.locator('.optimizer-snapshot')).toContainText(time)
      await expect(page.locator('.optimizer-snapshot')).toContainText(zone)
      await expect(page.locator('.optimizer-snapshot')).toContainText('Oct 15')
      await expect(page.locator('.demo-banner')).toHaveCount(0)
      await expect(page.locator('input[type="datetime-local"]')).toHaveCount(0)
    }
  }
})
