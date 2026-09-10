import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import vm from 'node:vm';

const root = fileURLToPath(new URL('../dist/', import.meta.url));
const html = readFileSync(join(root, 'index.html'), 'utf8');
const source = readFileSync(join(root, 'app.js'), 'utf8');

test('static entrypoint, local assets, anchors and SVG symbols resolve', () => {
  assert.match(html, /<html lang="zh-CN">/);
  assert.equal((html.match(/<h1\b/g) || []).length, 1);
  const ids = [...html.matchAll(/\bid="([^"]+)"/g)].map(match => match[1]);
  assert.equal(ids.length, new Set(ids).size, 'IDs must be unique');
  for (const [, reference] of html.matchAll(/(?:src|href)="([^"]+)"/g)) {
    if (reference.startsWith('#')) {
      if (reference.length > 1) assert.ok(ids.includes(reference.slice(1)), reference);
    } else assert.ok(existsSync(join(root, reference)), reference);
  }
  const css = readFileSync(join(root, 'styles.css'), 'utf8');
  for (const [, asset] of css.matchAll(/url\(['"]?([^'"\)]+)['"]?\)/g)) assert.ok(existsSync(join(root, asset)), asset);
  new vm.Script(source);
  new vm.Script(readFileSync(join(root, 'config.js'), 'utf8'));
});

function setup(config = {}) {
  let now = 0;
  let interval;
  class Element {
    constructor() { this.attributes = {}; this.events = {}; this.textContent = ''; this.hidden = true; }
    setAttribute(name, value) { this.attributes[name] = value; }
    removeAttribute(name) { delete this.attributes[name]; }
    addEventListener(name, handler) { this.events[name] = handler; }
    replaceChildren(...children) { this.children = children; }
    showModal() { this.open = true; }
    close() { this.open = false; }
    fire(name) { this.events[name]?.({ target: this, preventDefault() {} }); }
  }
  const nodes = Object.fromEntries(['app-store-link', 'download-label', 'download-status', 'contact-link', 'goal-progress', 'goal-percent', 'timer-toggle', 'timer-digits', 'timer-status', 'info-dialog', 'dialog-title', 'dialog-content'].map(id => [id, new Element()]));
  const boxes = Array.from({ length: 5 }, (_, i) => Object.assign(new Element(), { checked: i < 3 }));
  const stores = [new Element(), nodes['app-store-link']];
  const buttons = ['privacy', 'usage'].map(name => Object.assign(new Element(), { dataset: { dialog: name } }));
  const close = new Element();
  const groups = { '.goal-tasks input': boxes, '.store-button': stores, '[data-dialog]': buttons };
  let navigated;
  const context = {
    URL, performance: { now: () => now }, setInterval: fn => { interval = fn; },
    window: { ZHOUJI_CONFIG: config, location: { assign: url => { navigated = url; } } },
    document: {
      querySelector: selector => selector === '.dialog-close' ? close : nodes[selector.slice(1)],
      querySelectorAll: selector => groups[selector], createElement: () => new Element(),
    },
  };
  vm.runInNewContext(source, context);
  return { nodes, boxes, stores, buttons, close, advance: ms => { now += ms; interval(); }, get navigated() { return navigated; } };
}

test('goal completion supports all complete, undo and zero complete', () => {
  const { nodes, boxes } = setup();
  boxes[3].checked = true; boxes[3].fire('change');
  assert.equal(nodes['goal-percent'].textContent, '80%');
  boxes[4].checked = true; boxes[4].fire('change');
  assert.equal(nodes['goal-progress'].value, 5);
  assert.equal(nodes['goal-percent'].textContent, '100%');
  boxes.forEach(box => { box.checked = false; }); boxes[0].fire('change');
  assert.equal(nodes['goal-progress'].value, 0);
  assert.equal(nodes['goal-percent'].textContent, '0%');
});

test('timer uses elapsed time and excludes paused time', () => {
  const { nodes, advance } = setup();
  advance(42000);
  assert.equal(nodes['timer-digits'].textContent, '43:00');
  nodes['timer-toggle'].fire('click'); advance(60000);
  assert.equal(nodes['timer-digits'].textContent, '43:00');
  assert.equal(nodes['timer-toggle'].attributes['aria-label'], '继续专注演示');
  nodes['timer-toggle'].fire('click'); advance(2000);
  assert.equal(nodes['timer-digits'].textContent, '43:02');
  assert.equal(nodes['timer-toggle'].attributes['aria-label'], '暂停专注演示');
});

test('unconfigured and unsafe download links never navigate', () => {
  for (const url of ['', 'javascript:alert(1)', 'https://apps.apple.com.evil.example/app']) {
    const { nodes, stores } = setup({ appStoreUrl: url });
    nodes['app-store-link'].fire('click');
    assert.match(nodes['download-status'].textContent, /准备上架/);
    assert.ok(stores.every(store => !store.href));
    assert.equal(nodes['contact-link'].hidden, true);
  }
});

test('confirmed configuration connects download, contact and external policy', () => {
  const appStoreUrl = 'https://apps.apple.com/cn/app/id123456789';
  const page = setup({ appStoreUrl, contactEmail: 'hello@example.com', privacyUrl: 'https://example.com/privacy' });
  assert.ok(page.stores.every(store => store.href === appStoreUrl));
  assert.equal(page.nodes['contact-link'].href, 'mailto:hello@example.com');
  assert.equal(page.nodes['contact-link'].hidden, false);
  page.buttons[0].fire('click');
  assert.equal(page.navigated, 'https://example.com/privacy');
});

test('local explanations open, provide readable text and close', () => {
  const page = setup();
  page.buttons[0].fire('click');
  assert.equal(page.nodes['info-dialog'].open, true);
  assert.equal(page.nodes['dialog-title'].textContent, '隐私说明');
  assert.equal(page.nodes['dialog-content'].children.length, 3);
  page.close.fire('click');
  assert.equal(page.nodes['info-dialog'].open, false);
  page.buttons[1].fire('click');
  assert.equal(page.nodes['dialog-title'].textContent, '简单开始使用粥记');
});
