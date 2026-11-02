const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = fs.readFileSync(path.join(__dirname, '../lib/main.dart'), 'utf8');
const script = source.split("static const _playerScript = r'''\n")[1].split("''';")[0];
const updates = [];
const media = {
  paused: true, ended: false, currentSrc: 'test', duration: 120, currentTime: 0,
  volume: 0.7, playbackRate: 1,
  async play() { this.paused = false; }, pause() { this.paused = true; }
};
let skips = 0;
const root = {appendChild() {}};
const document = {
  title: 'Page', head: root, documentElement: root, addEventListener() {}, createElement: () => ({}),
  querySelector(selector) {
    if (selector === 'video, audio') return media;
    if (selector.startsWith('ytmusic-player-bar')) return {disabled: false, click() { skips++; }};
    return null;
  }
};
const window = {flutter_inappwebview: {callHandler(_, state) { updates.push(state); }}};
vm.runInNewContext(script, {
  window, document, navigator: {mediaSession: {metadata: {title: 'Song', artist: 'Artist'}}},
  setInterval() {}, MutationObserver: class { observe() {} }
});
(async () => {
  assert.equal(await window.__mytubeControl('play'), true);
  assert.equal(media.paused, false);
  assert.equal(await window.__mytubeControl('play'), true);
  assert.equal(media.paused, false, 'duplicate play must not toggle to pause');
  await window.__mytubeControl('pause');
  await window.__mytubeControl('pause');
  assert.equal(media.paused, true, 'duplicate pause must not restart playback');
  assert.equal(await window.__mytubeControl('seek', 500), true);
  assert.equal(media.currentTime, 120);
  assert.equal(await window.__mytubeControl('seek', -1), false);
  assert.equal(await window.__mytubeControl('next'), true);
  assert.equal(await window.__mytubeControl('previous'), true);
  assert.equal(skips, 2);
  assert.equal(await window.__mytubeControl('unsupported'), false);
  assert.equal(updates[0].trackTitle, 'Song');
  assert.equal(updates[0].artist, 'Artist');
  assert.equal(updates[0].duration, 120000, 'native duration uses milliseconds');
  assert.equal(updates.at(-1).position, 120000);
  assert.equal(media.volume, 0.7);
  assert.equal(media.playbackRate, 1);
  console.log('Passed transport commands, metadata, position, and audio-state checks.');
})().catch(error => { console.error(error); process.exitCode = 1; });
