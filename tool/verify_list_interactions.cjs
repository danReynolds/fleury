// Compile test/fixtures/list_interaction_web.dart in fleury_web and serve it
// alongside `fleury serve --spawn dart run test/fixtures/list_interaction_app.dart`.
// Run: PLAYWRIGHT_MODULE=/path/to/playwright node tool/verify_list_interactions.cjs
//      <browser-fixture-url> <served-fixture-url>
const assert = require('node:assert/strict');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');

async function verify(browser, url) {
  const page = await browser.newPage();
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  try {
    await page.goto(url);
    const rows = page.locator('.fleury-screen .fleury-row');
    const row = i => rows.nth(i);
    const waitText = async (i, value) => {
      await page.waitForFunction(({ i, value }) =>
        document.querySelectorAll('.fleury-screen .fleury-row')[i]
          ?.textContent.includes(value), { i, value });
    };
    await waitText(3, 'Choice 2');
    const cellWidth = await row(0).evaluate(element =>
      element.getBoundingClientRect().width / element.textContent.length);
    const move = async (col, index) => {
      const bounds = await row(index).boundingBox();
      await page.mouse.move(bounds.x + (col + 0.5) * cellWidth,
        bounds.y + bounds.height / 2);
    };
    await move(2, 2);
    await page.mouse.down();
    await waitText(0, 'Selected: 1; activated: none');
    // The selection callback rebuilt the parent before this release.
    await page.mouse.up();
    await waitText(0, 'Selected: 1; activated: 1');
    await move(2, 3);
    await page.mouse.down();
    await waitText(0, 'Selected: 2; activated: 1');
    await move(30, 3); // Outside the row's 20-column hit region.
    await page.mouse.up();
    // Allow the remote cancellation to complete, then drive another round trip.
    await page.waitForTimeout(150);
    assert.match(await row(0).innerText(), /Selected: 2; activated: 1/);
    await page.keyboard.press('ArrowUp');
    await waitText(0, 'Selected: 1; activated: 1');
    await page.keyboard.press('Enter');
    await waitText(0, 'Selected: 1; activated: 1');

    // Wheel movement can reach every line inside a single oversized item.
    await move(2, 7);
    const seen = new Set();
    for (let step = 0; step < 5; step++) {
      for (let i = 5; i < 10; i++) {
        const match = (await row(i).innerText()).match(/Line (\d)/);
        if (match) seen.add(Number(match[1]));
      }
      if (step < 4) {
        await page.mouse.wheel(0, 20);
        await waitText(5, `Line ${step + 1}`);
      }
    }
    assert.deepEqual([...seen].sort(), [0, 1, 2, 3, 4, 5, 6, 7]);
    assert.match(await row(9).innerText(), /Tail/);
    assert.match(await row(10).innerText(), /Outside the viewport/);
    assert.match(await row(0).innerText(), /Selected: 1; activated: 1/);
    await move(19, 5); // The scrollbar can return to the first content row.
    await page.mouse.click((await row(5).boundingBox()).x + 19.5 * cellWidth,
      (await row(5).boundingBox()).y + (await row(5).boundingBox()).height / 2);
    await waitText(5, 'Line 0');
    assert.deepEqual(errors, []);
    console.log(JSON.stringify({url, result: 'passed', checks: [
      'select on down', 'activate after parent rebuild on release',
      'cancel outside', 'keyboard focus retained', 'all tall-item lines reachable',
      'viewport clipping', 'wheel leaves selection alone', 'scrollbar returns to top',
    ]}));
  } finally {
    await page.close();
  }
}

(async () => {
  const urls = process.argv.slice(2);
  if (urls.length !== 2) throw new Error('Pass the browser and served fixture URLs.');
  const browser = await chromium.launch({
    ...(process.env.CHROME_EXECUTABLE ? {executablePath: process.env.CHROME_EXECUTABLE} : {}),
    headless: true,
  });
  try { for (const url of urls) await verify(browser, url); }
  finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
