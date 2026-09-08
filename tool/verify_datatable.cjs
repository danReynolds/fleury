// Exercise both DataTable documentation demos through browser input.
// PLAYWRIGHT_MODULE=/path/to/playwright CHROME_EXECUTABLE=/path/to/chrome \
//   node tool/verify_datatable.cjs http://127.0.0.1:4332/fleury/widgets/datatable/
const assert = require('node:assert/strict');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
(async () => {
  const url = process.argv[2];
  if (!url) throw new Error('Pass the running DataTable reference URL.');
  const browser = await chromium.launch({ headless: true,
    ...(process.env.CHROME_EXECUTABLE ? { executablePath: process.env.CHROME_EXECUTABLE } : {}) });
  try {
    const page = await browser.newPage({ viewport: { width: 1426, height: 899 }, colorScheme: 'dark' });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(url);
    const host = id => page.locator(`[data-fleury-example="${id}"]`);
    const screen = id => host(id).locator('.fleury-screen');
    const show = async id => { await host(id).scrollIntoViewIfNeeded(); await screen(id).waitFor(); };
    const waitText = async (id, text) => page.waitForFunction(({id, text}) =>
      document.querySelector(`[data-fleury-example="${id}"] .fleury-screen`)?.textContent.includes(text), {id, text}, {timeout: 5000}).catch(async error => {
        console.error(await screen(id).innerText());
        await page.screenshot({path: '/tmp/fleury-datatable-browser.png'});
        throw error;
      });
    const point = async (id, label) => {
      const row = screen(id).locator('.fleury-row').filter({ hasText: label }).first();
      await row.scrollIntoViewIfNeeded();
      const bounds = await row.boundingBox();
      const text = await row.textContent();
      return { x: bounds.x + (text.indexOf(label) + label.length / 2) * bounds.width / text.length,
        y: bounds.y + bounds.height / 2 };
    };
    const click = async (id, label, count = 1) => {
      const p = await point(id, label);
      await page.mouse.click(p.x, p.y, {clickCount: count, delay: 70});
    };

    await show('datatable.rows');
    await click('datatable.rows', 'Row 2');
    await waitText('datatable.rows', 'Chosen: Row 2');
    await page.keyboard.press('ArrowDown');
    await waitText('datatable.rows', 'Browsing: Row 3');
    assert.match(await screen('datatable.rows').innerText(), /Chosen: Row 2/);
    await page.mouse.wheel(0, 90);
    await page.waitForTimeout(100);
    assert.match(await screen('datatable.rows').innerText(), /Browsing: Row 3/);
    await page.keyboard.press('Enter');
    await waitText('datatable.rows', 'Chosen: Row 3');

    await show('datatable.cells');
    await click('datatable.cells', 'Row 2');
    await waitText('datatable.cells', 'Range: 1 × 1');
    assert.match(await screen('datatable.cells').innerText(), /No row opened/);
    await page.keyboard.press('Shift+ArrowRight');
    await page.keyboard.press('Shift+ArrowDown');
    await waitText('datatable.cells', 'Range: 2 × 2');
    await page.keyboard.press('ArrowDown');
    assert.match(await screen('datatable.cells').innerText(), /Range: 2 × 2/);
    await page.keyboard.press('Enter');
    await waitText('datatable.cells', 'Opened row 4');
    await click('datatable.cells', 'Row 2', 2);
    await waitText('datatable.cells', 'Opened row 2');
    const p = await point('datatable.cells', 'Row 3');
    await page.mouse.move(p.x, p.y);
    await page.mouse.down();
    await page.mouse.move(p.x + 100, p.y + 150, {steps: 6});
    await page.mouse.up();
    assert.match(await screen('datatable.cells').innerText(), /Opened row 2/);
    await page.screenshot({path: '/tmp/fleury-datatable-browser.png'});
    assert.deepEqual(errors, []);
    process.stdout.write('DataTable browser checks passed: row choice, keyboard browsing, wheel, cell range, Enter, double-click and cancelled drag.\n');
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
