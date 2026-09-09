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
    await page.waitForFunction(() => {
      const rows = document.querySelectorAll('[data-fleury-example="lists.files"] .fleury-row');
      const row = [...rows].find(row => row.textContent.trim() === 'sketches.txt');
      return row?.querySelector('span[style*="background"]');
    });
    assert.match(await screen('lists.files').innerText(), /Selected: notes.md/);
    await page.keyboard.press('Enter');
    await waitText('lists.files', 'Selected: sketches.txt');
    await host('lists.files').locator('xpath=ancestor::figure[contains(@class,"cds")]').screenshot({path: '/tmp/fleury-lists-first-demo.png'});

    await show('lists.tasks');
    await waitText('lists.tasks', 'Task 25');
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

    // The confirmed task keeps a visible cue after the browsing cursor moves.
    await page.keyboard.press('ArrowDown');
    await waitText('lists.tasks', '✓ Task 501');
    const chosen = screen('lists.tasks').locator('.fleury-row').filter({hasText: '✓ Task 501'}).first();
    const next = screen('lists.tasks').locator('.fleury-row').filter({hasText: /^\s*Task 502\s*$/}).first();
    const chosenStyle = await chosen.locator('span').filter({hasText: '✓ Task 501'}).first().getAttribute('style');
    assert.match(chosenStyle, /color:/);
    assert.notEqual(chosenStyle, await next.locator('span').filter({hasText: 'Task 502'}).first().getAttribute('style'));
    await page.keyboard.press('Enter');
    await waitText('lists.tasks', '✓ Task 502');
    assert.doesNotMatch(await screen('lists.tasks').innerText(), /✓ Task 501/);
    await host('lists.tasks').locator('xpath=ancestor::figure[contains(@class,"cds")]').screenshot({path: '/tmp/fleury-lists-task-browser-verified.png'});

    await show('datatable.rows');
    await click('datatable.rows', 'Row 2');
    await waitText('datatable.rows', 'Chosen: Row 2');
    await page.keyboard.press('ArrowDown');
    await waitText('datatable.rows', 'Browsing: Row 3');
    assert.match(await screen('datatable.rows').innerText(), /Chosen: Row 2/);
    await page.keyboard.press('Enter');
    await waitText('datatable.rows', 'Chosen: Row 3');
    await page.keyboard.press('PageDown');
    assert.match(await screen('datatable.rows').innerText(), /Name\s+Status/);

    await show('lists.horizontal');
    await click('lists.horizontal', 'Preview');
    await waitText('lists.horizontal', 'Selected: Preview');
    await page.keyboard.press('End');
    await waitText('lists.horizontal', 'Outline');
    await page.keyboard.press('Enter');
    await waitText('lists.horizontal', 'Selected: Outline');
    await page.keyboard.press('Home');
    await waitText('lists.horizontal', 'Editor');
    const galleryPoint = await point('lists.horizontal', 'Editor');
    await page.mouse.move(galleryPoint.x, galleryPoint.y);
    await page.mouse.wheel(240, 0);
    await page.waitForFunction(() => !document.querySelector('[data-fleury-example="lists.horizontal"] .fleury-screen').textContent.includes('Editor'));
    assert((await screen('lists.horizontal').textContent()).includes('Selected: Outline'));
    await page.keyboard.press('Home');
    await waitText('lists.horizontal', 'Editor');
    await page.keyboard.down('Shift');
    await page.mouse.wheel(0, 240);
    await page.keyboard.up('Shift');
    await page.waitForFunction(() => !document.querySelector('[data-fleury-example="lists.horizontal"] .fleury-screen').textContent.includes('Editor'));
    await host('lists.horizontal').locator('xpath=ancestor::figure[contains(@class,"cds")]').screenshot({path: '/tmp/fleury-horizontal-list-verified.png'});

    await show('lists.wide-content');
    await click('lists.wide-content', 'NAME');
    await page.keyboard.press('End');
    await waitText('lists.wide-content', '· END');
    assert((await screen('lists.wide-content').textContent()).includes('SUCCESS'));
    await page.keyboard.press('Home');
    await waitText('lists.wide-content', '· START');
    const reportPoint = await point('lists.wide-content', 'NAME');
    await page.mouse.move(reportPoint.x, reportPoint.y);
    await page.mouse.wheel(240, 0);
    await page.waitForFunction(() => !document.querySelector('[data-fleury-example="lists.wide-content"] .fleury-screen').textContent.includes('· START'));
    await page.keyboard.press('End');
    await waitText('lists.wide-content', '· END');
    await page.keyboard.press('Home');
    await waitText('lists.wide-content', '· START');
    // Box-drawing cells are CSS graphics, so they have no DOM text.
    const reportBar = screen('lists.wide-content').locator('.fleury-row').nth(4);
    const reportBarBounds = await reportBar.boundingBox();
    await page.mouse.move(reportBarBounds.x + reportBarBounds.width * 0.05, reportBarBounds.y + reportBarBounds.height / 2);
    await page.mouse.down();
    await page.mouse.move(reportBarBounds.x + reportBarBounds.width + 30, reportBarBounds.y + reportBarBounds.height / 2, {steps: 6});
    await page.mouse.up();
    await waitText('lists.wide-content', '· END');
    await host('lists.wide-content').locator('xpath=ancestor::figure[contains(@class,"cds")]').screenshot({path: '/tmp/fleury-horizontal-content-verified.png'});

    await show('lists.document');
    await waitText('lists.document', 'Rows 1–4 / 8 · TOP');
    await click('lists.document', 'Bubble (leave pane)');
    await host('lists.document').locator('[role="menu"]').waitFor({state: 'attached'});
    await page.keyboard.press('ArrowDown');
    await page.keyboard.press('Enter');
    await host('lists.document').locator('[role="menu"]').waitFor({state: 'detached'});
    await waitText('lists.document', 'Contain (stay in pane)');
    await page.keyboard.press('Tab');
    await page.keyboard.press('End');
    await waitText('lists.document', 'Rows 5–8 / 8 · BOTTOM');
    await page.keyboard.press('ArrowDown');
    await page.keyboard.press('Enter');
    assert.match(await screen('lists.document').innerText(), /Focus: scroll pane/);
    await host('lists.document').locator('xpath=ancestor::figure[contains(@class,"cds")]').screenshot({path: '/tmp/fleury-lists-edges-demo.png'});
    await click('lists.document', 'Contain (stay in pane)');
    await host('lists.document').locator('[role="menu"]').waitFor({state: 'attached'});
    await page.keyboard.press('ArrowUp');
    await page.keyboard.press('Enter');
    await host('lists.document').locator('[role="menu"]').waitFor({state: 'detached'});
    await waitText('lists.document', 'Bubble (leave pane)');
    await page.keyboard.press('Tab');
    await page.keyboard.press('End');
    await page.keyboard.press('ArrowDown');
    await host('lists.document').locator('[role="button"][aria-label="Next"][data-fleury-focused="true"]').waitFor({state: 'attached'});
    await page.keyboard.press('Enter');
    await waitText('lists.document', 'Next selected');

    assert.equal(await host('lists.log').count(), 0);
    assert.equal(await host('lists.reorder').count(), 0);
    assert.equal(await page.getByText('Complete source file', {exact: true}).count(), 0);
    assert.equal(await page.getByRole('heading', {name: 'Other layouts', exact: true}).count(), 0);

    // Complete files begin at the relevant widget, including after tab switches
    // and in the expanded playground. Their imports remain reachable above.
    const demo = host('lists.document').locator('xpath=ancestor::figure[contains(@class,"cds")]');
    const verifySourcePosition = async scope => {
      await page.waitForTimeout(100);
      const position = await scope.locator('[data-code-focus-line]').first().evaluate(source => {
        const scroll = source.closest('.cds-scroll');
        const line = source.querySelectorAll('.ec-line')[Number(source.dataset.codeFocusLine) - 1];
        return {top: line.getBoundingClientRect().top - scroll.getBoundingClientRect().top,
          height: scroll.clientHeight, offset: scroll.scrollTop};
      });
      assert.ok(position.offset > 0, 'Complete source should open partway through the file.');
      assert.ok(position.top >= 0 && position.top < position.height, 'Relevant widget should start in view.');
    };
    await verifySourcePosition(demo);
    await demo.getByRole('tab', {name: 'scroll_edges_test.dart', exact: true}).click();
    assert.match(await demo.innerText(), /contain keeps the edge arrow/);
    await demo.getByRole('tab', {name: 'scroll_edges.dart', exact: true}).click();
    await verifySourcePosition(demo);
    assert.match(await demo.innerText(), /class ScrollEdges/);
    await demo.locator('.cds-scroll').first().evaluate(el => {el.scrollTop = 0;});
    assert.match(await demo.innerText(), /import 'package:fleury/);
    await demo.getByRole('button', {name: 'Open the full playground', exact: true}).click();
    const modal = page.locator('dialog.cds-modal');
    await verifySourcePosition(modal);
    await modal.getByRole('button', {name: /Close/}).click();
    await demo.screenshot({path: '/tmp/fleury-lists-guide-verified.png'});
    assert.deepEqual(errors, []);
    console.log(JSON.stringify({result: 'passed', demos: 6, checks: [
      'selectable first list', 'horizontal list navigation and selection', 'native horizontal and Shift+wheel', 'wide content and bottom scrollbar', 'cursor vs viewport', 'click and Enter select; arrows browse',
      'persistent chosen row', 'table navigation and fixed header', 'edge containment and focus escape',
      'numbered viewport and edge markers', 'complete source positioned at the relevant code', 'source and test tabs',
    ]}));
  } catch (error) {
    await page.screenshot({path: '/tmp/fleury-lists-guide-failure.png'});
    console.error(await page.locator('[data-fleury-example] .fleury-screen').allInnerTexts());
    throw error;
  } finally { await browser.close(); }
})().catch(error => {console.error(error); process.exitCode = 1;});
