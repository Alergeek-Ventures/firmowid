(() => {
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const fmt = n => Math.round(n).toLocaleString('pl-PL', { useGrouping: 'always' }).replace(/ | /g, ' ');

  function tween(el, from, to, ms = 900, format = fmt) {
    if (reduce || document.hidden) { el.textContent = format(to); return; }
    const t0 = performance.now();
    const step = t => {
      const p = Math.min(1, (t - t0) / ms), e = 1 - Math.pow(1 - p, 3);
      el.textContent = format(from + (to - from) * e);
      if (p < 1) requestAnimationFrame(step);
    };
    requestAnimationFrame(step);
  }

  /* ---------- reveal + counters + bars ---------- */
  const io = new IntersectionObserver(es => es.forEach(e => {
    if (!e.isIntersecting) return;
    const el = e.target;
    el.classList.add('in');
    $$('.bar100', el).forEach(b => b.classList.add('go'));
    $$('[data-count]', el).forEach(c => tween(c, 0, +c.dataset.count, 1200, c.dataset.dec ? n => n.toFixed(1).replace('.', ',') : fmt));
    if (el.id === 'chat') startChat();
    if (el.id === 'tabs') startTabs();
    io.unobserve(el);
  }), { threshold: 0.18 });
  $$('.reveal').forEach(el => io.observe(el));

  /* ---------- timers ---------- */
  function tick(el, start) {
    let s = start;
    const draw = () => {
      const h = String(Math.floor(s / 3600)).padStart(2, '0'), m = String(Math.floor(s / 60) % 60).padStart(2, '0'), x = String(s % 60).padStart(2, '0');
      el.textContent = `${h}:${m}:${x}`;
    };
    draw(); setInterval(() => { s++; draw(); }, 1000);
  }
  tick($('#timer2'), 51 * 60 + 12);

  /* ---------- charts ---------- */
  const LABS = ['Sty', 'Lut', 'Mar', 'Kwi', 'Maj', 'Cze', 'Lip', 'Sie', 'Wrz', 'Paź', 'Lis', 'Gru'];
  function buildChart(root) {
    root.innerHTML = LABS.map(l => `<div class="col"><div class="col__area"><span class="col__val"></span><span class="col__bar"></span></div><div class="col__lab">${l}</div></div>`).join('');
    return $$('.col', root);
  }
  // values in thousands PLN; null = month not closed yet / no data
  function drawChart(cols, vals, delay = 60) {
    const maxP = Math.max(1, ...vals.filter(v => v > 0)), maxN = Math.max(0, ...vals.filter(v => v < 0).map(v => -v));
    const unit = Math.max(maxP / 62, maxN / 24);
    cols.forEach((c, i) => {
      const bar = $('.col__bar', c), val = $('.col__val', c), v = vals[i];
      bar.style.transitionDelay = val.style.transitionDelay = (i * delay) + 'ms';
      bar.className = 'col__bar';
      val.style.opacity = 0;
      if (v == null) { if (i === 10) { bar.classList.add('open'); bar.style.height = '22%'; } else bar.style.height = 0; val.textContent = ''; return; }
      const h = Math.abs(v) / unit;
      if (v < 0) bar.classList.add('neg');
      bar.style.height = h + '%';
      val.textContent = (v > 0 ? '' : '−') + String(Math.abs(v)).replace('.', ',');
      val.style.top = val.style.bottom = '';
      if (v < 0) val.style.top = `calc(${70 + h}% + 4px)`; else val.style.bottom = `calc(${30 + h}% + 4px)`;
      val.style.opacity = 1;
    });
  }
  function zeroChart(cols) { cols.forEach(c => { const b = $('.col__bar', c); b.style.transitionDelay = '0ms'; b.style.height = 0; $('.col__val', c).style.opacity = 0; }); }

  const firm = [12.4, 9.8, 15.1, 6.2, 11.9, 14.3, -4.2, 10.6, 21.6, 18.4, null, null];
  const c1 = buildChart($('#chart1'));
  const tip = document.createElement('div');
  tip.className = 'tip';
  tip.innerHTML = '<b>Lipiec 2026</b><span>Wynik <i>−4 210 zł</i></span><span>Przychody <i>52 300 zł</i></span><span>Wydatki <i>56 510 zł</i></span>';
  $('#chart1').append(tip);

  const projects = [
    { name: 'CODEXA', v: [7.1, 6.4, 8.8, 5.2, 7.9, 9.6, 2.1, 6.8, 11.2, 9.8, null, null], rev: 214000, cost: 139100, keep: 35 },
    { name: 'QUBIQ', v: [3.9, 2.2, 4.8, -1.4, 2.6, 3.1, -5.2, 1.9, 6.3, 4.4, null, null], rev: 151000, cost: 128400, keep: 15 },
    { name: 'Cała firma', v: firm, rev: 742000, cost: 625900, keep: 16 },
  ];
  const c2 = buildChart($('#chart2'));
  let pj = 0, pjTimer, pjPrev = { rev: 0, cost: 0 };
  function showProject(i, first) {
    const p = projects[i];
    $('#projchip').textContent = 'Pokaż: ' + p.name;
    drawChart(c2, p.v, first ? 60 : 0);
    const z = n => fmt(n) + ' zł';
    tween($('#pj-rev'), pjPrev.rev, p.rev, 700, z);
    tween($('#pj-cost'), pjPrev.cost, p.cost, 700, z);
    tween($('#pj-res'), pjPrev.rev - pjPrev.cost, p.rev - p.cost, 700, z);
    $('#pj-keep').textContent = `zostało ${p.keep} zł`;
    pjPrev = p;
  }

  /* ---------- inbox matching ---------- */
  let inboxT = [];
  function playInbox() {
    const hit = $('#duehit'), wire = $('#wire'), cnt = $('#duecount');
    inboxT.forEach(clearTimeout);
    hit.className = 'due'; wire.className = 'wire'; cnt.textContent = '3';
    const at = (ms, fn) => inboxT.push(setTimeout(fn, ms));
    at(900, () => wire.classList.add('go'));
    at(2200, () => { hit.classList.add('hit'); wire.classList.add('done'); });
    at(4300, () => { hit.classList.add('gone'); cnt.textContent = '2'; });
  }

  /* ---------- auto tabs ---------- */
  const tabs = $$('.tab'), panels = $$('.panel'), side = $$('.app__side li');
  let cur = -1, tabsOn = false, advanceTimer;
  const CAPS = [
    'Liczą się tylko opłacone faktury. Nieopłacone widzisz osobno, poza sumą.',
    'Miesiąc pojawia się na wykresie, gdy się skończy i najwyżej dwie jego faktury czekają na zapłatę.',
    'Koszt projektu to godziny zespołu razy stawka plus jego udział w kosztach firmy.',
    'Przelew z banku sam przypina się do faktury. Niepewne dopasowania zatwierdzasz jednym kliknięciem.',
  ];
  $('#tabcap').textContent = CAPS[0];
  function go(i) {
    clearTimeout(advanceTimer);
    cur = i;
    tabs.forEach((t, k) => { t.classList.remove('on'); if (k === i) { void t.offsetWidth; t.classList.add('on'); } t.setAttribute('aria-selected', k === i); });
    panels.forEach((p, k) => p.classList.toggle('on', k === i));
    side.forEach(li => li.classList.toggle('act', (li.dataset.m || '').includes(String(i))));
    $('#tabcap').textContent = CAPS[i];
    clearInterval(pjTimer); tip.classList.remove('show');
    if (i === 1) { zeroChart(c1); setTimeout(() => drawChart(c1, firm), 60); setTimeout(() => {
      if (cur !== 1) return;
      const col = c1[6], r = col.getBoundingClientRect(), R = $('#chart1').getBoundingClientRect();
      tip.style.left = Math.min(R.width - 184, Math.max(4, r.left - R.left + r.width + 6)) + 'px';
      tip.style.top = '34%';
      tip.classList.add('show');
    }, 1700); }
    if (i === 2) { pj = 0; pjPrev = { rev: 0, cost: 0 }; zeroChart(c2); setTimeout(() => showProject(0, true), 60);
      if (!reduce) pjTimer = setInterval(() => { pj = (pj + 1) % projects.length; showProject(pj); }, 2300); }
    if (i === 3) playInbox();
    if (i === 0) setTimeout(() => { if (cur === 0) point($('.panel.on .bar100--app .seg--keep')); }, 1500);
    if (i === 3) setTimeout(() => { if (cur === 3) point($('#duehit .due__ok')); }, 2600);
  }

  /* cursor that "uses" the app between tabs */
  const cursor = $('#cursor'), appEl = $('.app');
  function point(el, click) {
    if (!cursor || !el || !el.offsetParent || reduce) return false;
    const r = el.getBoundingClientRect(), R = appEl.getBoundingClientRect();
    cursor.style.opacity = 1;
    cursor.style.transform = `translate(${r.left - R.left + r.width / 2}px, ${r.top - R.top + r.height / 2}px)`;
    if (click) setTimeout(() => { cursor.classList.add('click'); setTimeout(() => cursor.classList.remove('click'), 260); }, 620);
    return true;
  }
  // what the cursor clicks to get to panel n
  const clickFor = n => [
    () => side.find(li => (li.dataset.m || '').includes('0')),
    () => $$('.panel.on .pill')[1],
    () => $('.panel.on .chip'),
    () => side.find(li => li.dataset.m === '3'),
  ][n]();
  function advance(n) {
    if (point(clickFor(n), true)) advanceTimer = setTimeout(() => go(n), 820); else go(n);
  }
  tabs.forEach((t, i) => {
    t.addEventListener('click', () => go(i));
    $('i', t).addEventListener('animationend', () => { if (!reduce && tabsOn && cur === i) advance((i + 1) % tabs.length); });
  });
  function startTabs() { tabsOn = true; go(0); }
  side.forEach(li => li.classList.toggle('act', (li.dataset.m || '').includes('0')));

  /* ---------- assistant chat ---------- */
  const QA = [
    { q: 'Który miesiąc był najsłabszy i dlaczego?', a: '<b>Lipiec: strata 4 210 zł.</b> Przychody spadły o 31%, a koszt podwykonawców został bez zmian.',
      mini: el => { el.className = 'mini'; el.innerHTML = firm.slice(0, 10).map(v => `<span class="${v < 0 ? 'neg' : ''}" data-h="${Math.abs(v) / 21.6 * 100}"></span>`).join(''); setTimeout(() => $$('span', el).forEach((s, i) => { s.style.transitionDelay = i * 40 + 'ms'; s.style.height = s.dataset.h + '%'; }), 60); } },
    { q: 'Na co idzie najwięcej moich pieniędzy?', a: '<b>Wynagrodzenia i ZUS: 41 zł</b> z każdych 100 zł przychodu. Dalej podwykonawcy, 18 zł.',
      mini: el => { el.className = 'mini bar'; const c = ['#9C5D39', '#DEA785', '#E9C3AC', '#666', '#5f8f4f'], w = [41, 18, 9, 9, 23]; el.innerHTML = w.map((_, i) => `<span style="background:${c[i]}"></span>`).join(''); setTimeout(() => $$('span', el).forEach((s, i) => { s.style.transitionDelay = i * 90 + 'ms'; s.style.width = `calc(${w[i]}% - 2px)`; }), 60); } },
    { q: 'Które koszty odbiegają od zwykłych?', a: '<b>Oprogramowanie i IT: 7 200 zł</b>, zwykle 5 100 zł (+41%). Doszły licencje dla dwóch osób.',
      mini: el => { el.className = 'mini cmp2'; el.innerHTML = '<span style="background:#D28F67;color:#000">Październik · 7 200 zł</span><span style="background:#555">Zwykle · 5 100 zł</span>'; setTimeout(() => { const s = $$('span', el); s[0].style.width = '92%'; s[1].style.width = '65%'; }, 60); } },
  ];
  const cq = $('#chat-q'), ca = $('#chat-a'), ct = $('#chat-text'), cm = $('#chat-mini'), chips = $$('#chat-chips button');
  let chatT = [], chatI = 0, chatStarted = false;
  function ask(i, instant) {
    chatT.forEach(clearTimeout); chatT = []; chatI = i;
    const { q, a, mini } = QA[i];
    chips.forEach((c, k) => c.classList.toggle('on', k === i));
    ca.classList.add('dim'); cq.textContent = '';
    const speed = reduce ? 0 : 32;
    if (instant) cq.textContent = q;
    else [...q].forEach((ch, k) => chatT.push(setTimeout(() => { cq.textContent += ch; }, 300 + k * speed)));
    const done = instant ? 0 : 300 + q.length * speed + 500;
    chatT.push(setTimeout(() => { ct.innerHTML = a; cm.innerHTML = ''; ca.classList.remove('dim'); ca.classList.add('show'); mini(cm); }, done));
    if (!reduce) chatT.push(setTimeout(() => ask((i + 1) % QA.length), done + 5200));
  }
  function startChat() { if (chatStarted) return; chatStarted = true; ask(0, true); }
  chips.forEach((c, i) => c.addEventListener('click', () => ask(i)));
  startChat();

  /* ---------- pricing toggle ---------- */
  $$('#billing button').forEach(b => b.addEventListener('click', () => {
    $$('#billing button').forEach(x => { x.classList.toggle('on', x === b); x.setAttribute('aria-pressed', x === b); });
    $('.plans').classList.toggle('yearly', b.dataset.b === 'y');
    $$('.plan__price b[data-m]').forEach(p => tween(p, +p.textContent, +p.dataset[b.dataset.b], 450));
  }));

  /* ---------- cost calculator ---------- */
  const cmpf = $('#cmpf');
  if (cmpf) {
    const v = id => +$('#' + id).value || 0, on = id => $('#' + id).checked;
    const people = n => n === 1 ? '1 osoba' : (n % 10 >= 2 && n % 10 <= 4 && (n < 12 || n > 14)) ? n + ' osoby' : n + ' osób';
    const zl = n => (n < 0 ? '−' : '') + fmt(Math.abs(n)) + ' zł';
    // what each ticked habit turns into in Firmowid
    const SWAP = [
      ['q-inv', 'Program do faktur', 'Faktury i KSeF bez limitu'],
      ['q-time', 'Program do czasu pracy', 'Czasośledź'],
      ['q-bank', 'Wpłaty sprawdzane ręcznie', 'Przelew sam przypina się do faktury'],
      ['q-sheet', 'Wynik w Excelu', 'Analiza: ile zostaje ze 100 zł'],
      ['q-leave', 'Urlopy w mailach', 'Wnioski z akceptacją'],
    ];
    let shown = 0, sayTimer;
    const calc = () => {
      const team = v('q-team'), h = v('q-h'), r = v('q-r'), share = v('q-s') / 100;
      // plan from the public price list, yearly billing
      const plan = team <= 2 && !on('q-leave') ? ['Darmowy', 0] : team <= 5 ? ['Przedsiębiorca', 276] : ['Firma', 1428];
      const now = ((on('q-inv') ? v('q-inv-p') : 0) + (on('q-time') ? v('q-time-p') : 0)) * 12;
      const hours = h * 52 * share, time = hours * r, total = now - plan[1] + time;
      $('#q-team-out').textContent = people(team);
      $('#q-h-out').textContent = String(h).replace('.', ',') + ' h';
      $('#q-r-out').textContent = r + ' zł';
      $('#q-s-out').textContent = Math.round(share * 100) + '%';
      $('#r-now').textContent = zl(now) + ' / rok';
      $('#r-plan').textContent = plan[0];
      $('#r-fw').textContent = zl(plan[1]) + ' / rok';
      $('#r-hours').textContent = fmt(hours);
      $('#r-time').textContent = zl(time);
      $('#r-swap').innerHTML = SWAP.filter(s => on(s[0])).map(s => `<li><s>${s[1]}</s><i>→</i><b>${s[2]}</b></li>`).join('');
      tween($('#r-total'), shown, total, 350, n => (n < 0 ? '−' : '') + fmt(Math.abs(n)));
      shown = total;
      clearTimeout(sayTimer);
      sayTimer = setTimeout(() => { $('#r-say').textContent = 'Z Firmowidem oszczędzasz rocznie ' + zl(total); }, 600);
    };
    cmpf.addEventListener('input', calc);
    cmpf.addEventListener('submit', e => e.preventDefault());
    calc();

    // one question at a time: later steps stay blurred until the earlier one is answered
    const steps = $$('.step', cmpf), out = $('#cmpout');
    const things = n => n === 1 ? '1 rzecz' : n >= 2 && n <= 4 ? n + ' rzeczy' : n + ' rzeczy';
    const summary = [
      () => $('#q-team-out').textContent,
      () => things($$('.opt > input:checked', cmpf).length),
      () => $('#q-h-out').textContent + ' tygodniowo',
    ];
    let reached = 0;
    const openStep = n => {
      reached = Math.max(reached, n);
      steps.forEach((s, i) => {
        s.classList.toggle('is-open', i === n);
        s.classList.toggle('is-locked', i > reached);
        s.classList.toggle('is-done', i < reached || (i <= reached && i !== n));
        $('.step__sum', s).textContent = i !== n && i <= reached ? summary[i]() : '';
      });
      if (reached === steps.length - 1) out.classList.remove('is-locked');
    };
    steps.forEach((s, i) => {
      const next = $('.step__next', s);
      if (next) next.addEventListener('click', () => openStep(i + 1));
      $('legend', s).addEventListener('click', () => { if (i <= reached) openStep(i); });
    });
    openStep(0);
  }
})();
