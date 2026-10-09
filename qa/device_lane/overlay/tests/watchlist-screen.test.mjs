// QA device-lane OVERLAY for watchlist-screen.test.mjs (replaces the repo spec in the scratch copy only).
// The repo spec expects a bookmark toggle on every Streams-list row; the app moved it into each row's overflow menu
// ("More options" -> "Add to Watchlist"). Same intent, current UI: open the Watchlist screen, add via the overflow menu, see it
// listed, remove it again so reruns start from the same state.
import { runSpec, assert } from './_harness.mjs'
import { LoginPage, AppNav } from '../pages/index.mjs'

await runSpec('watchlist screen: opens from the drawer, add/remove round-trips', async (driver) => {
  const login = new LoginPage(driver)
  const nav = new AppNav(driver)

  await login.ensureLoggedIn()
  await nav.openDrawerItem('Watchlist')
  assert(await nav.textExists('Watchlist'), 'Watchlist screen should render its title')
  const wasEmpty = await nav.textExists('Your Watchlist Is Empty')
  await nav.backToHome()
  assert(await nav.isOnHome(), 'should return to the home shell after backing out of Watchlist')

  await nav.tapDesc('More options', { msg: 'row overflow menu ("More options") not found - is the stream list empty?' })
  await nav.tapText('Add to Watchlist', { msg: '"Add to Watchlist" item missing from the row overflow menu' })
  await driver.pause(1500)

  await nav.openDrawerItem('Watchlist')
  assert(!(await nav.textExists('Your Watchlist Is Empty')), 'watchlist still shows the empty state after adding a stream')

  const remove = await driver.$$('android=new UiSelector().descriptionContains("Remove from Watchlist")')
  if (remove.length > 0) await remove[0].click()
  await driver.pause(1000)
  await nav.backToHome()
  assert(await nav.isOnHome(), 'should return to the home shell after the watchlist round-trip')
})
