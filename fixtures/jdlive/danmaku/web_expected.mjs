// Writes fixtures/jdlive/danmaku/S06-live/expected.json and
// S07-ended/expected.json: what the JD Live website's own chat code makes of
// the recordings (docs/modules/
// M5.24-jdlive.md, "与网页脚本的对照"). 3.x had no JD Live chat, the
// archived v4 had none either (spec/sites/jdlive.md §7: "不做"), and
// pure_live_TV's JD Live is `EmptyDanmaku`, so the website is the only
// earlier implementation.
//
// The functions below restate, one by one, the live page script as served
// on 2026-09-29 (storage.360buyimg.com/live-common/prod/jd-live/js/
// app-c714bc7b.340fdd69.js modules `cf45`, `b2eb` and the store, and
// live-f71cff67.44dc43c4.js, the chat list); the minified original is quoted
// above each. Only aes-js (the page's AES) is replaced with Node's crypto,
// the same AES-128-CBC with PKCS#7 padding.
//
// The harness encrypts the recorded liveauth content as the page does, reads
// the recorded answer as the page does (the socket URL and the mask key) and
// runs every received frame through the page's socket handler, its store and
// its chat list, writing per frame what the chat list adds, the viewer count
// the store keeps and whether the store ends the broadcast.
//
// Run from the repository root (Node 18 or later, no packages):
//
//   node fixtures/jdlive/danmaku/web_expected.mjs
//
// Review the diff of expected.json before committing it.
import { createCipheriv } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';

const samples = ['fixtures/jdlive/danmaku/S06-live', 'fixtures/jdlive/danmaku/S07-ended'];
const generator =
  "the JD Live page script of 2026-09-29 (app-c714bc7b.340fdd69.js: cf45 j, b2eb h/I/j/y, the store's pushMessage; " +
  'live-f71cff67.44dc43c4.js: the chat list agreementList and pushChat), restated in ' +
  'fixtures/jdlive/danmaku/web_expected.mjs, over the recorded liveauth request and answer and every received frame';

// app-c714bc7b cf45 exports u = {appId:"jd.mall",secretKey:"RYm2dMPMWD9AxYFk",pyl:"0102030405060708"}.
const config = { appId: 'jd.mall', secretKey: 'RYm2dMPMWD9AxYFk', pyl: '0102030405060708' };

// cf45 j(e,t): o=t||p.h.secretKey, r=utf8.toBytes(o), s=utf8.toBytes(p.h.pyl),
// u=pkcs7.pad(utf8.toBytes(e)), l=new cbc(r,s).encrypt(u); return btoa(hex bytes).
function encrypt(text, key) {
  const cipher = createCipheriv('aes-128-cbc', Buffer.from(key || config.secretKey, 'utf8'), Buffer.from(config.pyl, 'utf8'));
  return Buffer.concat([cipher.update(Buffer.from(text, 'utf8')), cipher.final()]).toString('base64');
}

// b2eb h(): o.m({appId:r.h.appId,content:Object(c.c)(JSON.stringify(l))}), then on
// 0===g&&w: f=w.msgMaskKey, b("".concat(w.liveUrl,"?token=").concat(w.token)).
function answer(text) {
  const { code, data } = JSON.parse(text);
  if (!(code === 0 && data)) return null;
  return { socket: `${data.liveUrl}?token=${data.token}`, mask: data.msgMaskKey, secretPin: data.secretPin };
}

// b2eb y(e): for(...) t.push(e.charCodeAt(i)); return new Uint8Array(t).
function bytesOf(text) {
  return new Uint8Array([...(text || '')].map((c) => c.charCodeAt(0)));
}

// b2eb j(e,t): t[i]=e[i%e.length]^t[i]; n+="%"+_(t[a].toString(16)); decodeURIComponent(n).
function unmask(key, data) {
  for (let i = 0; i < data.length; i++) data[i] = key[i % key.length] ^ data[i];
  let n = '';
  for (const byte of data) n += '%' + byte.toString(16).padStart(2, '0');
  return decodeURIComponent(n);
}

// b2eb I(t): i=t.data; if(i instanceof Blob) i=j(y(f), bytes); try{dispatch("pushMessage",JSON.parse(i))}catch{}.
function onMessage(data, mask) {
  try {
    const text = typeof data === 'string' ? data : unmask(bytesOf(mask), Uint8Array.from(data));
    return JSON.parse(text);
  } catch {
    return undefined;
  }
}

// Store mutation pushMessage(e,t): switch(t.body.type){... case"stop_live_broadcast":
// status 2} ... "get_statistics_result"===t.type&&(e.live.viewer=t.body.total_viwer).
function store(chat, state) {
  if (chat.body.type === 'stop_live_broadcast') state.status = 2;
  if (chat.type === 'get_statistics_result') state.viewer = chat.body.total_viwer;
}

// Chat list: agreementList:["viewer_send_message","anchor_send_message"];
// watch chat: this.agreementList.includes(e.body.type)&&this.pushChat(e);
// pushChat: e.from.secretPin!==this.messageAuto.secretPin&& push({content:e.body.content,
// nickName:"anchor_send_message"===e.body.type?"主播":e.body.nickName, type:e.body.type, ...}).
const agreementList = ['viewer_send_message', 'anchor_send_message'];
function chatList(chat, ownSecretPin) {
  if (!agreementList.includes(chat.body.type)) return [];
  if (chat.from.secretPin === ownSecretPin) return [];
  return [
    {
      type: chat.body.type,
      nickName: chat.body.type === 'anchor_send_message' ? '主播' : chat.body.nickName,
      content: chat.body.content,
    },
  ];
}

for (const sample of samples) {
  const lines = readFileSync(`${sample}/frames.jsonl`, 'utf8')
    .split('\n')
    .filter((line) => line.length > 0)
    .map((line) => JSON.parse(line));
  let auth = null;
  let content = null;
  const frames = [];
  lines.forEach((line, index) => {
    if (line.dir === 'out' && line.url) {
      content = { plain: line.content, encrypted: encrypt(line.content) };
      return;
    }
    if (line.dir !== 'in') return;
    if (line.url) {
      auth = answer(line.text);
      return;
    }
    const chat = onMessage(line.text ?? Buffer.from(line.b64, 'base64'), auth.mask);
    const state = {};
    const added = chat && chat.body ? chatList(chat, auth.secretPin) : [];
    if (chat && chat.body) store(chat, state);
    frames.push({ line: index + 1, chat: added, ...state });
  });

  const expected = {
    generator,
    value: {
      content: content.encrypted,
      socket: auth.socket,
      mask: auth.mask ?? null,
      frames,
    },
  };
  writeFileSync(`${sample}/expected.json`, JSON.stringify(expected, null, 2) + '\n');
  console.log(`${sample}: ${frames.length} frames, ${frames.reduce((n, f) => n + f.chat.length, 0)} chat lines`);
}
