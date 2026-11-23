/* Spitball site: themes, desktop windows, the playable app, ID cards, live numbers. */
(() => {
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const M = window.Motion;
  if (reduce) document.documentElement.classList.add('reduced');
  if (!M) document.documentElement.classList.add('no-motion');
  const store = {
    get(k, d) { try { const v = localStorage.getItem('spitball-' + k); return v == null ? d : JSON.parse(v); } catch (e) { return d; } },
    set(k, v) { try { localStorage.setItem('spitball-' + k, JSON.stringify(v)); } catch (e) {} },
  };
  const fmt = n => n >= 1e6 ? (n / 1e6).toFixed(1).replace(/\.0$/, '') + 'M' : n >= 1e4 ? Math.round(n / 1e3) + 'K' : n.toLocaleString();

  // ---------- themes ----------
  const themes = { pacific: '#66b3f5', grape: '#6b2edb', lagoon: '#0d5c6e', mint: '#126b4d' };
  function setTheme(t) {
    if (!themes[t]) return;
    document.documentElement.dataset.theme = t;
    $$('.swatch').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.t === t)));
    const meta = $('meta[name="theme-color"]'); if (meta) meta.content = themes[t];
    store.set('theme', t);
  }
  $$('.swatch').forEach(b => b.addEventListener('click', () => setTheme(b.dataset.t)));
  setTheme(store.get('theme', 'pacific'));

  // ---------- 1997 date + marquee ----------
  const d = new Date();
  const date = $('#date');
  if (date) date.textContent = d.toLocaleDateString('en-US', { weekday: 'short', day: '2-digit', month: 'short' }).replace(',', '').toUpperCase() + ' 1997';
  const mq = $('#marquee');
  if (mq) {
    const bits = ['Free forever', 'Open source', '100% on-device', 'Double-tap ⌘', 'Lives in your notch', 'Now with Command Mode', 'No account. No subscription.', 'Wispr Flow alternative'];
    mq.innerHTML = [...bits, ...bits].map(b => `<span>${b} ☼</span>`).join('');
  }

  // ---------- desktop windows: open, close, drag, focus ----------
  let z = 10;
  const focusWin = w => { w.style.zIndex = ++z; };
  function openWin(id) {
    const w = document.getElementById(id); if (!w) return;
    w.classList.add('open'); w.style.display = 'block'; focusWin(w);
    if (M && !reduce) M.animate(w, { opacity: [0, 1], scale: [0.92, 1] }, { duration: 0.35, ease: [0.2, 1.3, 0.4, 1] });
    if (innerWidth <= 1100 && id !== 'w-card') w.scrollIntoView({ behavior: reduce ? 'auto' : 'smooth', block: 'center' });
    const f = w.querySelector('input, button:not(.box)'); if (id === 'w-card' && f) setTimeout(() => f.focus(), 50);
  }
  function closeWin(id) {
    const w = document.getElementById(id); if (!w) return;
    const done = () => { w.classList.remove('open'); if (id === 'w-card') w.style.display = 'none'; };
    if (M && !reduce) M.animate(w, { opacity: 0, scale: 0.94 }, { duration: 0.18 }).then(() => { done(); w.style.opacity = ''; w.style.transform = ''; });
    else done();
  }
  $$('[data-open]').forEach(b => b.addEventListener('click', e => { e.preventDefault(); openWin(b.dataset.open); }));
  $$('[data-close]').forEach(b => b.addEventListener('click', () => closeWin(b.dataset.close)));
  document.addEventListener('keydown', e => { if (e.key === 'Escape' && $('#w-card')?.classList.contains('open') && !rec.active) closeWin('w-card'); });

  $$('.desk .win').forEach(w => {
    w.addEventListener('pointerdown', () => focusWin(w));
    const bar = w.querySelector('.bar');
    bar.addEventListener('pointerdown', e => {
      if (innerWidth <= 1100 || e.target.closest('button')) return;
      const desk = w.parentElement.getBoundingClientRect(), r = w.getBoundingClientRect();
      const dx = e.clientX - r.left, dy = e.clientY - r.top;
      w.classList.add('dragging'); bar.setPointerCapture(e.pointerId);
      const move = ev => {
        w.style.left = Math.max(-r.width + 80, Math.min(desk.width - 80, ev.clientX - desk.left - dx)) + 'px';
        w.style.top = Math.max(0, Math.min(desk.height - 40, ev.clientY - desk.top - dy)) + 'px';
        w.style.right = 'auto'; w.style.translate = 'none';
      };
      const up = () => { w.classList.remove('dragging'); bar.removeEventListener('pointermove', move); bar.removeEventListener('pointerup', up); };
      bar.addEventListener('pointermove', move); bar.addEventListener('pointerup', up);
    });
  });

  // ---------- Motion: entrances, reveals, the flying spitball ----------
  if (M && !reduce) {
    M.animate('#w-hello', { y: [30, 0], rotate: [-2, 0] }, { duration: 0.7, ease: [0.2, 1.2, 0.4, 1] });
    M.animate('#w-app', { y: [40, 0], rotate: [2, 0] }, { duration: 0.7, delay: 0.15, ease: [0.2, 1.2, 0.4, 1] });
    M.animate('.dock', { opacity: [0, 1], y: [30, 0] }, { duration: 0.5, delay: 0.35 });
    M.animate('.scene .logo', { scale: [0.6, 1], rotate: [-14, -6] }, { duration: 0.9, delay: 0.25, ease: [0.2, 1.5, 0.4, 1] });
    const ball = $('#flyball'), sun = $('#sun'), drink = $('#drink');
    if (ball) M.animate(0, 1, { duration: 1.2, delay: 0.4, ease: [0.2, 0.8, 0.3, 1], onUpdate: p => ball.setAttribute('transform', `translate(${620 - 230 * p} ${40 + 30 * p}) rotate(${-200 * p})`) })
      .then(() => M.animate(0, 1, { duration: 1.3, repeat: Infinity, repeatType: 'mirror', ease: 'easeInOut', onUpdate: p => ball.setAttribute('transform', `translate(390 ${70 - 12 * p}) rotate(${-200 + 8 * p})`) }));
    if (sun) M.animate(0, 1, { duration: 1.4, ease: 'easeOut', onUpdate: p => sun.setAttribute('cy', 302 - 40 * p) });
    if (drink) M.animate(0, 1, { duration: 1.5, repeat: Infinity, repeatType: 'mirror', ease: 'easeInOut', onUpdate: p => drink.setAttribute('transform', `translate(305 ${175 - 4 * p}) rotate(${3 * p})`) });
    M.inView('.reveal', info => { const el = info.target || info; M.animate(el, { opacity: [0, 1], y: [24, 0] }, { duration: 0.6, ease: [0.2, 1, 0.4, 1] }); }, { amount: 0.2 });
    M.inView('.steps', info => { const el = info.target || info; M.animate(el.querySelectorAll('.kbd'), { y: [0, 4, 0] }, { duration: 0.3, delay: M.stagger(0.18), repeat: 2 }); });
    $$('.dock svg').forEach(s => s.parentElement.addEventListener('mouseenter', () => M.animate(s, { rotate: [0, -12, 8, 0], scale: [1, 1.15, 1] }, { duration: 0.5 })));
  } else {
    $$('.reveal').forEach(el => { el.style.opacity = 1; el.style.transform = 'none'; });
  }

  // ---------- the playable app ----------
  const island = $('#island'), L = $('#barsL'), R = $('#barsR'), cw = $('#caretwave'), lcd = $('#lcdwave');
  if (island) {
    for (let i = 0; i < 9; i++) { L.appendChild(document.createElement('i')); R.appendChild(document.createElement('i')); }
    for (let i = 0; i < 5; i++) cw.appendChild(document.createElement('i'));
  }
  const lBars = island ? [...L.children].reverse() : [], rBars = island ? [...R.children] : [], cBars = island ? [...cw.children] : [];
  const taper = [.55, .7, .85, .95, 1, .95, .85, .7, .55];
  const lcdHist = Array(120).fill(0);
  // Voice Memos-style scrolling waveform on the LCD: one column per frame, mirrored around the centre.
  function drawLCD() {
    if (!lcd) return;
    const g = lcd.getContext('2d'), W = lcd.width, H = lcd.height, col = getComputedStyle(document.documentElement).getPropertyValue('--bottom').trim();
    g.clearRect(0, 0, W, H);
    const step = W / lcdHist.length;
    g.fillStyle = col;
    lcdHist.forEach((v, i) => {
      const h = Math.max(2, v * (H - 6));
      g.globalAlpha = 0.35 + 0.65 * (i / lcdHist.length);   // older samples fade out
      g.beginPath(); g.roundRect(i * step + 0.5, (H - h) / 2, Math.max(1.5, step - 2), h, 1.5); g.fill();
    });
    g.globalAlpha = 1;
  }
  drawLCD();
  function draw(levels, loud = levels.reduce((a, b) => a + b, 0) / levels.length) {
    levels.forEach((v, i) => { const h = Math.max(3, v * taper[i] * 18) + 'px'; lBars[i].style.height = h; rBars[i].style.height = h; });
    [2, 3, 4, 5, 6].forEach((b, i) => cBars[i].style.height = Math.max(3, levels[b] * 13) + 'px');
    lcdHist.push(loud); lcdHist.shift(); drawLCD();
  }

  const typed = $('#typed'), interim = $('#interim'), hint = $('#hint'), live = $('#live'), talk = $('#talk'), kcmd = $('#kcmd');
  const history = store.get('history', []);
  const words = store.get('words', ['TestFlight', 'GraphQL']);
  let style = 'spoken';
  const rec = { active: false, start: 0, stream: null, ctx: null, sr: null, text: '', raf: 0, fake: 0 };

  function say(t) { if (live) live.textContent = t; }
  function stats() {
    const w = history.reduce((a, h) => a + h.text.split(/\s+/).filter(Boolean).length, 0);
    const secs = history.reduce((a, h) => a + h.secs, 0);
    $('#s-words').textContent = fmt(w);
    $('#s-wpm').textContent = secs > 1 ? Math.round(w / (secs / 60)) : 0;
    $('#s-takes').textContent = history.length;
  }
  function renderHistory() {
    const p = $('#p-history');
    if (!history.length) return;
    p.innerHTML = history.slice(0, 20).map((h, i) => `<div class="row"><div><div class="meta">📝 Notes · ${new Date(h.at).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })}</div><p>${h.text.replace(/</g, '&lt;')}</p></div><button class="btn" data-copy="${i}">Copy</button></div>`).join('');
    $$('[data-copy]', p).forEach(b => b.addEventListener('click', async () => {
      try { await navigator.clipboard.writeText(history[+b.dataset.copy].text); b.textContent = 'Copied!'; say('Copied'); } catch (e) { b.textContent = 'Oops'; }
    }));
  }
  function renderWords() {
    $('#wordlist').innerHTML = words.map(w => `<span class="chip">${w.replace(/</g, '&lt;')}</span>`).join('');
  }
  // Same idea as the app: "TestFlight" also fixes "test flight".
  function applyWords(s) {
    for (const w of words) {
      const parts = w.match(/[A-Z]+(?=[A-Z][a-z])|[A-Z]?[a-z]+|[A-Z]+|\d+/g) || [w];
      const pat = parts.map(p => p.length <= 4 && p === p.toUpperCase() && /^[A-Z]+$/.test(p) ? p.split('').join('[\\s.]*') : p.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('[\\s-]*');
      s = s.replace(new RegExp(`(^|[^\\w])${pat}(?![\\w])`, 'gi'), (m, pre) => pre + w);
    }
    return s;
  }
  function applyStyle(s) {
    s = s.replace(/(^|\s)(um+|uh+|erm)[,.]?(?=\s|$)/gi, '$1').replace(/\s{2,}/g, ' ').trim();
    if (!s) return s;
    s = s[0].toUpperCase() + s.slice(1);
    if (style === 'texting') return s.toLowerCase().replace(/[.!]$/, '');
    if (style === 'casual') return s.replace(/\bdo not\b/gi, "don't").replace(/\bI am\b/g, "I'm").replace(/\bcannot\b/gi, "can't");
    if (style === 'formal') return (s.replace(/\bcan't\b/gi, 'cannot').replace(/\bdon't\b/gi, 'do not').replace(/\bI'm\b/g, 'I am').replace(/\bgonna\b/gi, 'going to').replace(/\bu\b/g, 'you')).replace(/([^.!?])$/, '$1.');
    return /[.!?]$/.test(s) ? s : s + '.';
  }

  /// A pretend voice that actually sounds like talking: syllables (~5 per second) in words,
  /// with short gaps between words and longer breaths between phrases.
  function fakeVoice() {
    let t = 0, env = 0, target = 0, until = 0, gapUntil = 0, syll = 0;
    return () => {
      t += 1 / 60;
      if (t > until) {
        if (t < gapUntil) target = 0;
        else {
          syll++;
          if (syll % (3 + (syll % 3)) === 0) { gapUntil = t + (syll % 11 === 0 ? 0.45 : 0.14); target = 0; }   // word / breath gap
          else target = 0.45 + Math.random() * 0.55;
          until = t + 0.11 + Math.random() * 0.12;
        }
      }
      env += (target - env) * (target > env ? 0.45 : 0.2);
      return Math.max(0, env * (0.85 + 0.15 * Math.random()));
    };
  }

  const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
  const demoLines = ['Running five minutes late, start standup without me.', 'Ship the new onboarding tonight, can someone review the PR?', 'Demo day dry run moved to Thursday at 3 pm.'];

  async function startRec() {
    if (rec.active) return;
    rec.active = true; rec.start = performance.now(); rec.text = ''; rec.noMic = false;
    typed.textContent = ''; interim.textContent = '';
    island.classList.add('open'); island.classList.remove('working'); cw.classList.add('on'); talk.classList.add('live');
    talk.textContent = '■ Release to finish';
    hint.textContent = SR ? 'Listening… just talk.' : 'Listening… (your browser can’t transcribe, so we’ll fake the words)';
    say('Listening');
    try {
      rec.stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      rec.ctx = new AudioContext();
      const an = rec.ctx.createAnalyser(); an.fftSize = 1024;
      rec.ctx.createMediaStreamSource(rec.stream).connect(an);
      const data = new Uint8Array(an.frequencyBinCount), hz = rec.ctx.sampleRate / an.fftSize, td = new Uint8Array(an.fftSize);
      let floorR = 0.02, peakR = 0.08;
      const edges = [90, 220, 450, 900, 1800, 4000], floor = Array(5).fill(255), peak = Array(5).fill(0), sm = Array(5).fill(0);
      const tick = () => {
        if (!rec.active) return;
        an.getByteFrequencyData(data);
        const b = [0, 1, 2, 3, 4].map(i => {
          let s = 0, c = 0;
          for (let j = Math.max(1, Math.floor(edges[i] / hz)); j < Math.floor(edges[i + 1] / hz); j++) { s += data[j]; c++; }
          const v = c ? s / c : 0;
          floor[i] = Math.min(floor[i] + 0.3, v); peak[i] = Math.max(peak[i] - 0.6, v, floor[i] + 30);
          const t = Math.max(0, Math.min(1, (v - floor[i] - 4) / (peak[i] - floor[i] - 4)));
          sm[i] += (t - sm[i]) * (t > sm[i] ? 0.6 : 0.18);
          return sm[i];
        });
        an.getByteTimeDomainData(td);
        let sum = 0; for (const v of td) { const x = (v - 128) / 128; sum += x * x; }
        const rms = Math.sqrt(sum / td.length);
        floorR = Math.min(floorR + 0.0004, rms); peakR = Math.max(peakR * 0.995, rms, floorR + 0.03);
        draw([4, 3, 2, 1, 0, 1, 2, 3, 4].map(i => b[i]), Math.max(0, Math.min(1, (rms - floorR) / (peakR - floorR))));
        rec.raf = requestAnimationFrame(tick);
      };
      tick();
    } catch (e) {
      // No mic: animate a pretend voice so the demo still feels alive.
      const voice = fakeVoice();
      const fake = () => {
        if (!rec.active) return;
        const loud = voice();
        draw(Array.from({ length: 9 }, (_, i) => Math.min(1, loud * (0.55 + 0.45 * Math.random()) * (i === 4 ? 1 : 0.9))), loud);
        rec.raf = requestAnimationFrame(fake);
      };
      fake();
      rec.noMic = true;
      hint.textContent = 'No mic access, so here’s a pretend voice.';
    }
    if (SR && !rec.noMic) {
      try {
        rec.sr = new SR(); rec.sr.continuous = true; rec.sr.interimResults = true; rec.sr.lang = navigator.language || 'en-US';
        rec.sr.onresult = ev => {
          let fin = '', tmp = '';
          for (const r of ev.results) (r.isFinal ? (fin += r[0].transcript) : (tmp += r[0].transcript));
          rec.text = fin; interim.textContent = tmp;
        };
        rec.sr.onerror = () => {};
        rec.sr.start();
      } catch (e) { rec.sr = null; }
    }
  }

  async function stopRec(cancel) {
    if (!rec.active) return;
    rec.active = false; cancelAnimationFrame(rec.raf);
    cw.classList.remove('on'); talk.classList.remove('live'); talk.textContent = '🎙 Hold to talk';
    island.classList.add('working');
    const secs = (performance.now() - rec.start) / 1000;
    if (rec.sr) { try { rec.sr.stop(); } catch (e) {} await new Promise(r => setTimeout(r, 450)); }
    rec.stream?.getTracks().forEach(t => t.stop()); rec.ctx?.close();
    draw(Array(9).fill(0));
    island.classList.remove('open', 'working');
    if (cancel) { hint.textContent = 'Cancelled.'; say('Cancelled'); interim.textContent = ''; return; }
    let text = (rec.text + ' ' + interim.textContent).trim();
    interim.textContent = '';
    if (!text && (!SR || rec.noMic)) text = demoLines[history.length % demoLines.length];
    if (!text) { hint.textContent = 'Didn’t catch that. Try again!'; say('Didn’t catch that'); return; }
    text = applyStyle(applyWords(text));
    typed.textContent = text;
    history.unshift({ text, secs: Math.max(secs, 1), at: Date.now() }); store.set('history', history.slice(0, 50));
    renderHistory(); stats();
    hint.textContent = 'Pasted. Now imagine that in every app.';
    say('Inserted: ' + text);
    if (M && !reduce) M.animate('#field', { scale: [1, 1.03, 1] }, { duration: 0.3 });
  }

  if (talk) {
    talk.addEventListener('pointerdown', e => { e.preventDefault(); talk.setPointerCapture(e.pointerId); startRec(); });
    talk.addEventListener('pointerup', () => stopRec(false));
    talk.addEventListener('pointercancel', () => stopRec(true));
    talk.addEventListener('keydown', e => { if ((e.key === ' ' || e.key === 'Enter') && !e.repeat) { e.preventDefault(); rec.active ? stopRec(false) : startRec(); } });

    // Double-tap ⌘ to start, tap ⌘ to finish, just like the app.
    let down = 0, lastTap = 0, clean = true;
    addEventListener('keydown', e => {
      if (e.key === 'Meta') { down = performance.now(); clean = true; kcmd.classList.add('down'); if (rec.active) { stopRec(false); clean = false; } }
      else { clean = false; if (e.key === 'Escape' && rec.active) stopRec(true); }
    });
    addEventListener('keyup', e => {
      if (e.key !== 'Meta') return;
      kcmd.classList.remove('down');
      const now = performance.now();
      if (!clean || now - down > 300) { lastTap = 0; return; }
      if (now - lastTap < 400) { lastTap = 0; if (!rec.active) startRec(); } else lastTap = now;
    });

    $$('.app-tabs [role=tab]').forEach(t => t.addEventListener('click', () => {
      $$('.app-tabs [role=tab]').forEach(o => { o.setAttribute('aria-selected', String(o === t)); document.getElementById(o.getAttribute('aria-controls')).hidden = o !== t; });
    }));
    $$('input[name=style]').forEach(r => r.addEventListener('change', () => { style = r.value; }));
    $('#wordform').addEventListener('submit', e => {
      e.preventDefault(); const v = $('#wordin').value.trim();
      if (v && !words.includes(v)) { words.unshift(v); store.set('words', words.slice(0, 20)); renderWords(); }
      $('#wordin').value = '';
    });
    renderHistory(); renderWords(); stats();
  }

  // ---------- ID card ----------
  const card = $('#idcard');
  function hash(s) { let h = 2166136261; for (const c of s) { h ^= c.charCodeAt(0); h = Math.imul(h, 16777619); } return Math.abs(h); }
  const me = store.get('card', { name: '', no: 0 });
  function printCard(raw) {
    raw = (raw || '').trim();
    let name = raw || 'Your Name';
    $('#c-name').textContent = name;
    const no = (raw && me.no && me.name === raw) ? me.no : (hash(name) % 90000 + 1000);
    $('#c-no').textContent = 'NO. ' + String(no).padStart(5, '0');
    $('#c-since').textContent = new Date().toLocaleDateString('en-US', { month: 'short', year: 'numeric' });
    store.set('card', { name: raw, no: raw ? no : 0 });
  }
  if (card) {
    printCard(me.name);
    $('#cardname').value = me.name;
    $('#cardform').addEventListener('submit', e => {
      e.preventDefault(); printCard($('#cardname').value);
      if (M && !reduce) M.animate(card, { rotateY: [0, 360] }, { duration: 0.9, ease: [0.3, 1.2, 0.4, 1] });
    });
    // Holographic tilt
    const tilt = (x, y) => { card.style.setProperty('--ry', ((x - .5) * 24) + 'deg'); card.style.setProperty('--rx', ((.5 - y) * 18) + 'deg'); card.style.setProperty('--gx', x * 100 + '%'); card.style.setProperty('--gy', y * 100 + '%'); };
    card.addEventListener('pointermove', e => { const r = card.getBoundingClientRect(); tilt((e.clientX - r.left) / r.width, (e.clientY - r.top) / r.height); });
    card.addEventListener('pointerleave', () => tilt(.5, .5));
    if (!reduce) { let t = 0; setInterval(() => { if (card.matches(':hover')) return; t += .03; tilt(.5 + Math.sin(t) * .25, .5 + Math.cos(t * .7) * .2); }, 50); }

    const site = 'https://itsnicksimpson.github.io/spitball/';
    $('#c-x').addEventListener('click', () => {
      const text = `Just got my Spitball Club ID ${$('#c-no').textContent} ☼ Free, open-source dictation for Mac. Double-tap ⌘, talk, done. No subscription.`;
      open(`https://x.com/intent/post?text=${encodeURIComponent(text)}&url=${encodeURIComponent(site)}`, '_blank', 'noopener');
    });
    $('#c-dl').addEventListener('click', async () => {
      const blob = await renderCardPNG(); const a = document.createElement('a');
      a.href = URL.createObjectURL(blob); a.download = 'spitball-id.png'; a.click(); setTimeout(() => URL.revokeObjectURL(a.href), 2000);
    });
    $('#c-copy').addEventListener('click', async e => {
      const b = e.currentTarget;
      try { await navigator.clipboard.write([new ClipboardItem({ 'image/png': renderCardPNG() })]); b.textContent = 'Copied! Paste it in a post'; }
      catch (err) { b.textContent = 'Use Download instead'; }
      setTimeout(() => b.textContent = 'Copy image', 2200);
    });
  }

  // Draw the card on a canvas so people can post the image.
  async function renderCardPNG() {
    await document.fonts.ready;
    const W = 1200, H = 756, c = document.createElement('canvas'); c.width = W; c.height = H;
    const g = c.getContext('2d'), ink = getComputedStyle(document.documentElement).getPropertyValue('--ink').trim();
    g.beginPath(); g.roundRect(0, 0, W, H, 52); g.save(); g.clip();
    const bg = g.createLinearGradient(0, 0, W, H);
    bg.addColorStop(0, '#fffdf6'); bg.addColorStop(.38, '#f4ecff'); bg.addColorStop(.68, '#e6faff'); bg.addColorStop(1, '#fff1e2');
    g.fillStyle = bg; g.fillRect(0, 0, W, H);
    // Holographic foil stripes
    const holo = g.createLinearGradient(0, H, W, 0);
    ['#ff9ad5', '#ffd36b', '#8ff0c6', '#7cc8ff', '#b48cff', '#ff9ad5'].forEach((col, i, a) => holo.addColorStop(i / (a.length - 1), col));
    g.globalAlpha = .28; g.fillStyle = holo;
    for (let x = -H; x < W + H; x += 16) { g.save(); g.translate(x, 0); g.rotate(.42); g.fillRect(0, -200, 7, H * 2); g.restore(); }
    g.globalAlpha = 1;
    // One big debossed wordmark, edge to edge
    g.textAlign = 'center'; g.textBaseline = 'middle';
    let size = 520; g.font = size + 'px Yellowtail';
    while (g.measureText('Spitball').width > W * 0.94 && size > 200) { size -= 8; g.font = size + 'px Yellowtail'; }
    g.save(); g.translate(W / 2, H / 2 - 20);
    g.fillStyle = 'rgba(18,18,31,.22)'; g.fillText('Spitball', -3, -3);
    g.fillStyle = 'rgba(255,255,255,.95)'; g.fillText('Spitball', 3, 3);
    g.fillStyle = 'rgba(18,18,31,.07)'; g.fillText('Spitball', 0, 0);
    g.restore();
    g.textAlign = 'left'; g.textBaseline = 'alphabetic'; g.fillStyle = ink;
    g.font = '700 30px "IBM Plex Mono"'; g.letterSpacing = '8px'; g.fillText('MEMBER', 56, 82);
    g.textAlign = 'right'; g.fillText($('#c-no').textContent, W - 56, 82);
    g.textAlign = 'left'; g.font = '700 40px "IBM Plex Mono"'; g.letterSpacing = '7px';
    g.fillText($('#c-name').textContent.toUpperCase(), 56, H - 90);
    g.font = '500 26px "IBM Plex Mono"'; g.globalAlpha = .6; g.fillText('SINCE ' + $('#c-since').textContent.toUpperCase(), 56, H - 48);
    g.globalAlpha = .85; g.letterSpacing = '0px';
    let x = W - 300; const pat = [2, 1, 3, 1, 2, 2, 1, 3, 1, 1, 2, 3];
    for (let i = 0; x < W - 56; i++) { const w = pat[i % pat.length] * 4; if (i % 2 === 0) g.fillRect(x, H - 110, w, 62); x += w + 4; }
    g.globalAlpha = .5; g.font = '500 20px "IBM Plex Mono"'; g.textAlign = 'center'; g.fillText('itsnicksimpson.github.io/spitball', W / 2, H - 22);
    g.restore(); g.beginPath(); g.roundRect(3, 3, W - 6, H - 6, 50); g.lineWidth = 6; g.strokeStyle = ink; g.stroke();
    return new Promise(r => c.toBlob(r, 'image/png'));
  }
  window.spitballCardPNG = renderCardPNG;   // handy for debugging / embedding
  function mix(a, b, t) {
    const p = h => { h = h.replace('#', ''); if (h.length === 3) h = h.split('').map(x => x + x).join(''); return [0, 2, 4].map(i => parseInt(h.slice(i, i + 2), 16)); };
    const A = p(a), B = p(b); return 'rgb(' + A.map((v, i) => Math.round(v + (B[i] - v) * t)).join(',') + ')';
  }

  // ---------- live numbers: GitHub + (optional) Spitball Club API ----------
  const count = (el, to) => {
    if (!el) return;
    if (!M || reduce) { el.textContent = fmt(to); return; }
    M.animate(0, to, { duration: 1.4, ease: [0.2, 0.9, 0.3, 1], onUpdate: v => { el.textContent = fmt(Math.round(v)); } });
  };
  fetch('https://api.github.com/repos/itsnicksimpson/spitball').then(r => r.ok ? r.json() : null).then(j => {
    if (!j) return;
    if (j.stargazers_count >= 25) { count($('#n-stars'), j.stargazers_count); const s = $('#stars-inline'); if (s) s.textContent = fmt(j.stargazers_count) + ' ★'; }
    else { $('#n-stars').textContent = 'New'; $('#n-stars').nextElementSibling.textContent = 'be an early star'; }
  }).catch(() => {});
  fetch('https://api.github.com/repos/itsnicksimpson/spitball/releases').then(r => r.ok ? r.json() : null).then(rel => {
    if (!rel) return; const n = rel.reduce((a, r) => a + r.assets.reduce((b, x) => b + x.download_count, 0), 0);
    if (n >= 25) count($('#n-dl'), n); else if (rel[0]) { $('#n-dl').textContent = rel[0].tag_name; $('#n-dl').nextElementSibling.textContent = 'fresh off the press'; }
    const as = rel[0]?.assets || []; const asset = as.find(a => a.name.endsWith('.dmg')) || as.find(a => a.name.endsWith('.zip'));
    if (asset) $('#dl').href = asset.browser_download_url;
  }).catch(() => {});
  const api = $('meta[name="spitball-api"]')?.content;
  if (api) {
    fetch(api + '/v1/stats').then(r => r.ok ? r.json() : null).then(s => {
      if (!s) return;
      count($('#n-words'), s.words); $('#n-words-l').textContent = 'words spoken by members';
      count($('#n-hours'), Math.round(s.hours)); $('#n-hours-l').textContent = 'hours of talking';
      if (s.top?.length) {
        $('#leaderboard').hidden = false;
        $('#lb tbody').innerHTML = s.top.map((m, i) => `<tr><td>#${i + 1}</td><td>${(m.handle || 'Anonymous').replace(/</g, '&lt;')}</td><td>${fmt(m.words)}</td><td>${(m.seconds / 3600).toFixed(1)}</td></tr>`).join('');
      }
    }).catch(() => {});
  }

  // ---------- copy install ----------
  $('#copy')?.addEventListener('click', async e => {
    const b = e.currentTarget;
    try { await navigator.clipboard.writeText($('#cmd').textContent); b.textContent = 'Copied!'; } catch (err) { b.textContent = 'Select & copy'; }
    setTimeout(() => b.textContent = 'Copy', 1600);
    setTimeout(() => openWin('w-card'), 700);   // after "downloading", hand them their ID card
  });
  $('#dl')?.addEventListener('click', () => setTimeout(() => openWin('w-card'), 900));
})();
