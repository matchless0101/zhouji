import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const read = path => readFileSync(new URL(path, import.meta.url), 'utf8');
const association = JSON.parse(read('../dist/.well-known/apple-app-site-association'));

test('association identifies the configured iOS app and limits links to the WeChat path', () => {
  const project = read('../../ios/project.yml');
  const team = project.match(/DEVELOPMENT_TEAM: "([^"]+)"/)[1];
  const bundle = project.match(/PRODUCT_BUNDLE_IDENTIFIER: (\S+)/)[1];
  assert.deepEqual(association.applinks.apps, []);
  assert.equal(association.applinks.details.length, 1);
  const app = association.applinks.details[0];
  assert.equal(app.appID, `${team}.${bundle}`);
  assert.deepEqual(app.paths, ['/wechat/*']);
  assert.ok(Buffer.byteLength(JSON.stringify(association)) < 128 * 1024);
  const matches = path => app.paths.some(pattern => new RegExp('^' + pattern.replaceAll('*', '.*') + '$').test(path));
  for (const path of ['/wechat/', '/wechat/callback', '/wechat/edgefix/example']) assert.ok(matches(path));
  for (const path of ['/', '/assets/phones.png', '/wechat-other/', '/account/']) assert.equal(matches(path), false);
});

test('iOS entitlement and the HTTPS fallback use the same associated domain', () => {
  const entitlement = read('../../ios/ZhouJi/ZhouJi.entitlements');
  assert.match(entitlement, /<key>com.apple.developer.associated-domains<\/key>/);
  const domains = [...entitlement.matchAll(/<string>([^<]+)<\/string>/g)].map(match => match[1]);
  assert.deepEqual(domains, ['applinks:zhouji.xiangdangdang.top']);
  const fallback = new URL('../dist/wechat/index.html', import.meta.url);
  for (const [, asset] of readFileSync(fallback, 'utf8').matchAll(/(?:src|href)="([^"]+)"/g)) {
    const local = asset === '/' ? new URL('../dist/index.html', import.meta.url) : new URL(asset, fallback);
    assert.ok(existsSync(fileURLToPath(local)), asset);
  }
});
