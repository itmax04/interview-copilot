import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { once } from 'node:events';
import http from 'node:http';
import path from 'node:path';
import { tmpdir } from 'node:os';
import { setTimeout as sleep } from 'node:timers/promises';

// Run with Node.js 22+ and Chrome on macOS. Supply Resources or a signed app's Contents/Resources.
const [bundle = 'Resources', ...options] = process.argv.slice(2);
const chrome = process.env.COPILOT_TEST_CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const profile = await mkdtemp(path.join(tmpdir(), 'copilot-browser-'));
function tone(seconds) {
  const wav = Buffer.alloc(44 + 16000 * 2 * seconds);
  wav.write('RIFF'); wav.writeUInt32LE(wav.length - 8, 4); wav.write('WAVEfmt ', 8);
  wav.writeUInt32LE(16, 16); wav.writeUInt16LE(1, 20); wav.writeUInt16LE(1, 22);
  wav.writeUInt32LE(16000, 24); wav.writeUInt32LE(32000, 28); wav.writeUInt16LE(2, 32);
  wav.writeUInt16LE(16, 34); wav.write('data', 36); wav.writeUInt32LE(wav.length - 44, 40);
  for (let i = 0; i < (wav.length - 44) / 2; i++) {
    wav.writeInt16LE(i < 4800 ? 0 : Math.round(1000 * Math.sin(i * 2 * Math.PI * 520 / 16000)), 44 + i * 2);
  }
  return wav;
}
const shortTone = tone(3);
const longTone = tone(25);

async function until(check, label, time = 8000) {
  const end = Date.now() + time;
  let last;
  while (Date.now() < end) {
    last = await check();
    if (last) return last;
    await sleep(60);
  }
  throw new Error('Timed out: ' + label);
}

const browser = spawn(chrome, ['--headless=new', '--mute-audio', '--no-first-run',
  '--disable-background-networking', '--remote-debugging-port=0', '--user-data-dir=' + profile, 'about:blank'],
  {stdio:'ignore'});
const failures = [];
try {
  const port = await until(async () => (await readFile(path.join(profile, 'DevToolsActivePort'), 'utf8')
    .catch(() => '')).split('\n')[0], 'Chrome DevTools');
  const devtools = 'http://127.0.0.1:' + port;
  for (const kind of ['Interviewer', 'TestCall']) {
    const interview = kind === 'Interviewer';
    let page = await readFile(path.join(bundle, kind, 'index.html'), 'utf8');
    if (options.includes('--en')) {
      const strings = JSON.parse(await readFile(path.join(bundle, kind, 'en.json'), 'utf8'));
      page = page.replace('<script>', '<script>window.L10N=' + JSON.stringify(strings) + ';</script><script>');
    }
    const mediaScenarios = ['resumable WAV', 'failed WAV resume'];
    const scenarios = options.includes('--media-only') ? mediaScenarios :
      ['buffered through outage', 'lost acknowledgement', 'close during outage', ...mediaScenarios];
    if (!interview && !options.includes('--media-only')) scenarios.push('queue resumes after outage');
    for (const scenario of scenarios) {
      let offline = false, acceptedEnd = 0, lostEnd = 0, closeCalls = 0, starts = 0, closed = false, replays = 0, cancelled = false, interrupted = null;
      const clip = {id:'tone', language:'en', title:'Synthetic tone', text:'Synthetic fixture'};
      const queued = scenario === 'queue resumes after outage';
      const clips = queued ? [clip, {...clip, id:'tone-2', title:'Second tone'}] : [clip];
      let lostBegin = 0;
      let stage = 'setup', current = null, results = [];
      const state = () => ({ready:true, backend:'Fixture', source:'Fixture', message:'Ready', levelDB:-35,
        stage, count:1, index:1, turns:[], current, clips, results,
        answer:{text:'',partial:''}, autoFinish:0});
      const server = http.createServer((req, res) => {
        const route = new URL(req.url, 'http://127.0.0.1').pathname.slice('/fixture/'.length);
        const send = (status, data, type = 'application/json', headers = {}) => {
          res.writeHead(status, {'Content-Type':type, 'Cache-Control':'no-store', Connection:'close',
            'Content-Security-Policy':"default-src 'self'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; media-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'",
            ...headers});
          res.end(data);
        };
        const json = (value = state(), status = 200) => send(status, JSON.stringify(value));
        if (route === 'close') closeCalls++;
        if (offline || closed) {
          if (route.startsWith('ended')) lostEnd++;
          if (route.startsWith('begin/')) lostBegin++;
          req.socket.destroy();
          return;
        }
        if (!route) return send(200, page, 'text/html; charset=utf-8');
        if (route === 'state') return json();
        if (route === 'start' || route.startsWith('begin/')) {
          if (current?.phase === 'playing') return json({error:'Previous phrase is active'}, 409);
          starts++;
          stage = 'speaking';
          const selected = clips.find(c => route === 'begin/' + c.id) || clip;
          current = {id:'trial-' + starts, clipID:selected.id, text:selected.text, audio:true, phase:'playing'};
          return json();
        }
        if (route.startsWith('audio/')) {
          const cut = mediaScenarios.includes(scenario) && !replays && !cancelled;
          if (cut && scenario === 'failed WAV resume' && interrupted?.destroyed) {
            req.socket.destroy(); // State has recovered, but the original media transfer cannot resume.
            return;
          }
          const wav = mediaScenarios.includes(scenario) ? longTone : shortTone;
          const start = Number(/^bytes=(\d+)-/.exec(req.headers.range || '')?.[1] || 0);
          const headers = {'Accept-Ranges':'bytes', 'Content-Range':'bytes ' + start + '-' + (wav.length - 1) + '/' + wav.length};
          if (cut && start === 0) {
            interrupted = req.socket;
            res.writeHead(206, {...headers, 'Content-Type':'audio/wav', 'Content-Length':wav.length, 'Cache-Control':'no-store'});
            return res.write(wav.subarray(0, 44 + 32000 * 15));
          }
          return send(206, wav.subarray(start), 'audio/wav', headers);
        }
        if (route === 'replay') {
          replays++;
          return json();
        }
        if (route.startsWith('ended')) {
          if (current.phase === 'playing') {
            acceptedEnd++;
            const trial = current;
            trial.phase = 'waiting';
            setTimeout(() => {
              if (current !== trial || closed) return;
              if (interview) stage = 'answering';
              else {
                trial.phase = 'complete';
                results.push({trialID:trial.id, clipID:trial.clipID, language:clip.language,
                  reference:trial.text, recognized:trial.text, words:2, errors:0, wer:0});
              }
            }, 150);
          }
          if (scenario === 'lost acknowledgement' && !lostEnd) {
            lostEnd++;
            req.socket.destroy();
            return;
          }
          return json();
        }
        if (route === 'cancel' || route === 'stop') {
          cancelled = true;
          current = null;
          stage = 'setup';
          return json();
        }
        if (route === 'close') {
          closed = true;
          return json({});
        }
        json({error:'Missing fixture route'}, 404);
      });
      const listening = once(server, 'listening');
      server.listen(0, '127.0.0.1');
      await listening;
      const tab = await fetch(devtools + '/json/new?about:blank', {method:'PUT'}).then(r=>r.json());
      const ws = new WebSocket(tab.webSocketDebuggerUrl);
      await once(ws, 'open');
      let seq = 0;
      const pending = new Map();
      ws.onmessage = event => {
        const reply = JSON.parse(event.data);
        const complete = pending.get(reply.id);
        if (complete) { pending.delete(reply.id); complete(reply); }
      };
      const call = (method, params) => new Promise(resolve => {
        pending.set(++seq, resolve);
        ws.send(JSON.stringify({id:seq, method, params}));
      });
      const value = async (expression, userGesture = false) => {
        const {result} = await call('Runtime.evaluate', {expression, returnByValue:true, userGesture});
        if (result?.exceptionDetails) throw new Error(result.exceptionDetails.exception?.description || result.exceptionDetails.text);
        return result?.result.value;
      };
      const status = () => value('document.querySelector("#status")?.textContent');
      const isOffline = s => /Нет связи|connection/i.test(s || '');
      const isClosed = s => /^(?:Собеседование закрыто|Собеседование завершено|Звонок завершён|Interview closed|Interview finished|Call ended)\./.test(s || '');
      const record = async () => ({status:await status(), acceptedEnd, lostEnd, starts, closeCalls,
        replays, browser:await value('({ended:document.querySelector("audio").ended, time:document.querySelector("audio").currentTime, mediaError:document.querySelector("audio").error?.code, readyState:document.querySelector("audio").readyState, problem:document.querySelector("#problem").textContent, startDisabled:document.querySelector("#start").disabled})')});
      try {
        await call('Page.navigate', {url:'http://127.0.0.1:' + server.address().port + '/fixture/'});
        await until(() => value('document.querySelector("#start")?.disabled === false'), 'enabled start');
        await value('document.querySelector("#start").click()', true);
        await until(() => value('document.querySelector("audio").currentTime > 0.35'), 'advancing HTML audio');
        if (queued) {
          await until(() => value('document.querySelectorAll("#results .result").length === 1'), 'first result displayed');
          offline = true;
          server.closeAllConnections();
          await until(async () => isOffline(await status()), 'visible disconnection between phrases');
          await sleep(850);
          assert.equal(starts, 1);
          assert.equal(lostBegin, 0, 'next phrase should wait for a fresh state response');
          offline = false;
          await until(() => starts === 2 && current.clipID === 'tone-2', 'second phrase started on reconnect');
        } else if (mediaScenarios.includes(scenario)) {
          await value('document.querySelector("audio").playbackRate = 8');
          offline = true;
          assert.ok(interrupted, 'WAV socket opened during playback');
          interrupted.destroy();
          await until(async () => isOffline(await status()), 'visible disconnection during transfer');
          await until(() => value('(() => {const a=document.querySelector("audio");return a.error !== null || (!a.ended && a.currentTime > 1 && a.readyState < HTMLMediaElement.HAVE_FUTURE_DATA)})()'),
            'Chrome stopped at the end of the partial WAV buffer', 12000);
          console.log(kind, 'interrupted WAV', JSON.stringify(await record()));
          offline = false;
          if (scenario === 'failed WAV resume') {
            const retry = interview ? '#retry' : '#repeat';
            await until(() => value('(() => {const b=document.querySelector("' + retry + '");return !b.disabled && b.checkVisibility() && document.querySelector("#problem").textContent.length > 0})()'), 'enabled playback retry');
            await value('document.querySelector("' + retry + '").click()', true);
            await until(() => interview ? replays === 1 : starts === 2, 'restarted same question or phrase');
            await until(() => value('document.querySelector("audio").currentTime < 2'), 'replay started near beginning');
            await value('document.querySelector("audio").playbackRate = 8');
          } else {
            await until(() => value('document.querySelector("audio").currentTime > 16'), 'resumed original WAV without replay', 7000);
          }
        } else if (scenario !== 'lost acknowledgement') {
          offline = true;
          server.closeAllConnections();
          if (scenario === 'close during outage') {
            await until(async () => isOffline(await status()), 'visible disconnection');
            await value('document.querySelector("#close").click()', true);
            await until(() => closeCalls > 0, 'close sent');
            await until(async () => isClosed(await status()) || await value('document.querySelector("#close").disabled === false'),
              'close attempt settled');
            assert.equal(isClosed(await status()), false, 'close success requires acknowledgement');
            assert.match(await status(), /Завершение не подтверждено|Could not confirm/);
            offline = false;
            await value('document.querySelector("#close").click()', true);
            await until(() => closed, 'retry close after reconnect');
            await until(async () => isClosed(await status()), 'confirmed close in the page');
            assert.equal(await value('document.querySelector("#audio").paused'), true);
          } else {
            await until(() => value('document.querySelector("audio").ended'), 'audio reached EOF while disconnected');
            await sleep(400);
            const disconnected = await record();
            assert.equal(disconnected.browser.ended, true);
            assert.ok(isOffline(disconnected.status), JSON.stringify(disconnected));
            console.log(kind, 'offline', JSON.stringify(disconnected));
            offline = false;
          }
        } else {
          await until(() => lostEnd > 0, 'response dropped after application accepted end');
        }
        if (scenario !== 'close during outage') {
          await until(async () => interview ? /Ваш ответ|Your answer/i.test(await status()) :
            /Проверка завершена|Test complete|Check complete|Check finished|Test finished/i.test(await status()),
            'natural next state after reconnection', 7000);
          assert.equal(acceptedEnd, queued ? 2 : 1);
          if (!interview) assert.equal(await value('document.querySelectorAll("#results .result").length'), queued ? 2 : 1);
          await value('document.querySelector("#close").click()', true);
          await until(() => closed, 'acknowledged close');
          await until(async () => isClosed(await status()), 'confirmed close in the page');
        }
        console.log('PASS', kind, scenario, JSON.stringify(await record()));
      } catch (error) {
        failures.push(kind + ' ' + scenario);
        console.log('FAIL', kind, scenario, error.message, JSON.stringify(await record()));
      } finally {
        ws.close();
        await fetch(devtools + '/json/close/' + tab.id).catch(() => {});
        await new Promise(resolve => server.close(resolve));
      }
    }
  }
} finally {
  browser.kill();
  if (browser.exitCode == null && browser.signalCode == null) await once(browser, 'exit');
  await rm(profile, {recursive:true, force:true, maxRetries:8, retryDelay:200});
}
if (failures.length) process.exitCode = 1;
