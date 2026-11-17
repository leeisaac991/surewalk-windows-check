// SURE Walk - Windows laptop check, portable Node part (the texting server).
// Run by RUN-CHECK.cmd as: node node-check.js <work folder>. Prints RESULT lines.
// Tests what server.mjs needs: modern Node, the vm module, a local-only web server, file writes,
// the America/Chicago time zone, and reaching GroupMe from Node (Node ignores the Windows proxy setting).
'use strict';
const http = require('http'), fs = require('fs'), path = require('path'), vm = require('vm');
const res = (k, s, d) => console.log(`RESULT ${k} ${s} ${d}`);
const work = process.argv[2] || require('os').tmpdir();

const major = Number(process.versions.node.split('.')[0]);
res('node-run', 'PASS', `node ${process.version} runs`);
if (major < 18) res('node-version', 'FAIL', 'Node 18 or newer needed - use the current LTS zip');

try {
  const out = vm.runInNewContext('var o = {}; o.x = [1,2,3].map(function(n){return n*2}); o', {});
  res('node-vm', out.x[2] === 6 ? 'PASS' : 'FAIL', 'runs the Apps Script files the way the server does');
} catch (e) { res('node-vm', 'FAIL', e.message); }

try {
  const f = path.join(work, 'node-w.tmp'); fs.writeFileSync(f, 'x'); fs.unlinkSync(f);
  res('node-files', 'PASS', 'can save its data in ' + work);
} catch (e) { res('node-files', 'FAIL', e.message); }

process.env.TZ = 'America/Chicago';
const h = new Date(Date.UTC(2026, 0, 15, 12, 0, 0)).getHours();
res('node-timezone', h === 6 ? 'PASS' : 'WARN', h === 6 ? 'Central time works' : `Central time not applied (got hour ${h}) - small server fix needed`);

const server = http.createServer((q, r) => r.end('ok'));
server.on('error', e => { res('node-loopback', 'FAIL', e.message); net(); });
server.listen(0, '127.0.0.1', () => {
  http.get(`http://127.0.0.1:${server.address().port}/`, r => {
    let b = ''; r.on('data', c => b += c);
    r.on('end', () => { res('node-loopback', b === 'ok' ? 'PASS' : 'FAIL', 'the local dashboard server works without admin or firewall prompts'); server.close(); net(); });
  }).on('error', e => { res('node-loopback', 'FAIL', e.message); server.close(); net(); });
});

async function net() {
  if (typeof fetch !== 'function') { res('node-groupme', 'WARN', 'this Node has no fetch - use a newer zip'); return; }
  try {
    const r = await fetch('https://api.groupme.com/v3/groups', { signal: AbortSignal.timeout(12000) });
    res('node-groupme', 'PASS', `GroupMe reachable from Node (HTTP ${r.status})`);
  } catch (e) {
    res('node-groupme', 'FAIL', 'GroupMe not reachable from Node: ' + ((e.cause && e.cause.code) || e.message));
  }
}
