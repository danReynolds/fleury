// Run against the built guide preview with real browser pointer/keyboard input.
// PLAYWRIGHT_MODULE=/path/to/playwright CHROME_EXECUTABLE=/path/to/chrome \
//   node tool/verify_lists_guide.cjs http://127.0.0.1:4332/fleury/guides/lists-and-scrolling/
const assert = require('node:assert/strict');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');

(async () => {
  const url = process.argv[2];
  if (!url) throw new Error('Pass the running Lists & scrolling guide URL.');
  const browser = await chromium.launch({
    headless: true,
    ...(process.env.CHROME_EXECUTABLE ? {executablePath: process.env.CHROME_EXECUTABLE} : {}),
  });
  const page = await browser.newPage({viewport: {width: 1426, height: 899}, colorScheme: 'dark'});
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  try {
    await page.goto(url);
    const host = id => page.locator(`[data-fleury-example="${id}"]`);
    const screen = id => host(id).locator('.fleury-screen');
    const waitText = async (id, value) => {
      await page.waitForFunction(({id, value}) =>
        document.querySelector(`[data-fleury-example="${id}"] .fleury-screen`)
          ?.textContent.includes(value), {id, value});
    };
    const point = async (id, label) => {
      const row = screen(id).locator('.fleury-row').filter({hasText: label}).first();
      await row.scrollIntoViewIfNeeded();
      const bounds = await row.boundingBox();
      const text = await row.textContent();
      const column = text.indexOf(label) + label.length / 2;
      return {x: bounds.x + column * bounds.width / text.length, y: bounds.y + bounds.height / 2};
    };
    const click = async (id, label) => {
      const p = await point(id, label);
      await page.mouse.click(p.x, p.y);
    };
    const show = async id => {
      await host(id).scrollIntoViewIfNeeded();
      await screen(id).waitFor();
    };

    await show('lists.files');
    await click('lists.files', 'notes.md');
    await waitText('lists.files', 'Selected: notes.md');
    await page.keyboard.press('ArrowDown');
    await waitText('lists.files', '› sketches.txt');
    assert.match(await screen('lists.files').innerText(), /Selected: notes.md/);
    await page.keyboard.press('Enter');
    await waitText('lists.files', 'Selected: sketches.txt');
    await host('lists.files').locator('xpath=ancestor::figure[contains(@class,"cds")]').screenshot({path: '/tmp/fleury-lists-first-demo.png'});

    await show('lists.tasks');
    await waitText('lists.tasks', '› Task 25');
    await waitText('lists.tasks', 'Selected: None');
    await click('lists.tasks', 'Go to 25');
    await waitText('lists.tasks', 'Current: 25 / 1000');
    await waitText('lists.tasks', 'Focused: outside list');
    assert.doesNotMatch(await screen('lists.tasks').innerText(), /Selected: Task/);
    await click('lists.tasks', 'Scroll to 500');
    await waitText('lists.tasks', 'Showing: 500–509');
    assert.match(await screen('lists.tasks').innerText(), /Current: 25 \/ 1000/);
    await click('lists.tasks', 'Go to 25');
    await waitText('lists.tasks', 'Showing: 25–34');
    assert.doesNotMatch(await screen('lists.tasks').innerText(), /Selected: Task/);
    await click('lists.tasks', 'Scroll to 500');
    await waitText('lists.tasks', 'Showing: 500–509');
    await click('lists.tasks', 'Task 500');
    await waitText('lists.tasks', 'Selected: Task 500');
    await page.keyboard.press('ArrowDown');
    await waitText('lists.tasks', 'Current: 501 / 1000');
    await waitText('lists.tasks', 'Focused: Task 501');
    assert.match(await screen('lists.tasks').innerText(), /Selected: Task 500/);
    await page.keyboard.press('Enter');
    await waitText('lists.tasks', 'Selected: Task 501');
    await host('lists.tasks').locator('xpath=ancestor::figure[contains(@class,"cds")]').screenshot({path: '/tmp/fleury-lists-task-browser-verified.png'});

    await show('lists.reorder');
    await click('lists.reorder', 'Reverse order');
    await waitText('lists.reorder', 'Current: Build the prototype');
    await page.waitForFunction(() =>
      document.querySelector('[data-fleury-example="lists.reorder"] .fleury-screen')
        ?.textContent.indexOf('Ship the guide') < document.querySelector('[data-fleury-example="lists.reorder"] .fleury-screen')
        ?.textContent.indexOf('Build the prototype'));
    await click('lists.reorder', 'Test the keyboard path');
    await waitText('lists.reorder', 'Current: Test the keyboard path');
    await click('lists.reorder', 'Reverse order');
    await waitText('lists.reorder', 'Current: Test the keyboard path');
    await page.waitForFunction(() => document.querySelectorAll('[data-fleury-example="lists.reorder"] .fleury-row')[1]?.textContent.includes('Sketch the layout'));
    const order = await screen('lists.reorder').innerText();
    assert.ok(order.indexOf('Sketch the layout') < order.indexOf('› Test the keyboard path'));

    await show('lists.document');
    await waitText('lists.document', 'Rows 1–4 / 8 · TOP');
    await click('lists.document', 'Contain arrows');
    await host('lists.document').locator('[role="checkbox"][aria-checked="true"]').waitFor({state: 'attached'});
    await page.keyboard.press('Tab');
    await page.keyboard.press('End');
    await waitText('lists.document', 'Rows 5–8 / 8 · BOTTOM');
    await page.keyboard.press('ArrowDown');
    await page.keyboard.press('Enter');
    assert.match(await screen('lists.document').innerText(), /Focus: scroll pane/);
    await host('lists.document').locator('xpath=ancestor::figure[contains(@class,"cds")]').screenshot({path: '/tmp/fleury-lists-edges-demo.png'});
    await click('lists.document', 'Contain arrows');
    await host('lists.document').locator('[role="checkbox"][aria-checked="false"]').waitFor({state: 'attached'});
    await page.keyboard.press('Tab');
    await page.keyboard.press('End');
    await page.keyboard.press('ArrowDown');
    await host('lists.document').locator('[role="button"][data-fleury-focused="true"]').waitFor({state: 'attached'});
    await page.keyboard.press('Enter');
    await waitText('lists.document', 'Next selected');

    assert.equal(await host('lists.log').count(), 0);
    const overflow = await page.locator('.cds-pane[data-pane="code"] [data-cds-code-file="0"] .expressive-code:first-child').evaluateAll(blocks =>
      blocks.flatMap((block, index) => [...block.querySelectorAll('.ec-line')]
        .filter(line => line.getBoundingClientRect().height > parseFloat(getComputedStyle(line).lineHeight) * 1.5)
        .map(line => ({demo: index, text: line.textContent})))
    );
    assert.deepEqual(overflow, [], 'Displayed source lines should fit without forced wrapping.');

    // The source/test tabs and complete-file disclosure work at the guide size.
    const demo = host('lists.reorder').locator('xpath=ancestor::figure[contains(@class,"cds")]');
    await demo.getByRole('tab', {name: 'reorder_tasks_test.dart', exact: true}).click();
    assert.match(await demo.innerText(), /reversing keeps the current task/);
    await demo.getByRole('tab', {name: 'reorder_tasks.dart', exact: true}).click();
    await demo.getByText('Complete source file', {exact: true}).click();
    assert.match(await demo.innerText(), /class ReorderTasks/);
    await demo.screenshot({path: '/tmp/fleury-lists-guide-verified.png'});
    assert.deepEqual(errors, []);
    console.log(JSON.stringify({result: 'passed', demos: 4, checks: [
      'selectable first list', 'cursor vs viewport', 'click and Enter select; arrows browse',
      'stable cursor through reorder', 'edge containment and focus escape',
      'numbered viewport and edge markers', 'source fits its pane', 'source and test tabs',
    ]}));
  } catch (error) {
    await page.screenshot({path: '/tmp/fleury-lists-guide-failure.png'});
    console.error(await page.locator('[data-fleury-example] .fleury-screen').allInnerTexts());
    throw error;
  } finally { await browser.close(); }
})().catch(error => {console.error(error); process.exitCode = 1;});
