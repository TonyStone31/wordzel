// Wordzel web - the same game as the desktop build, in the browser.
// Word data arrives from /words.js (generated from the Pascal units).

'use strict';

const $ = id => document.getElementById(id);

// ---- word machinery, mirroring unitwordpicker ----------------------------

const GUESSES = new Set(WZ_WORDS);
WZ_HOUSE.forEach(w => GUESSES.add(w));
const POTTY = new Set(WZ_POTTY);

const REJECT_FRACTION = 0.5;
const POOLS = {};            // len -> eligible secrets, most common first
for (let len = 3; len <= 9; len++) {
  const all = WZ_COMMON.filter(w => w.length === len);
  POOLS[len] = all.slice(0, Math.max(1, all.length - Math.trunc(all.length * REJECT_FRACTION)));
}
const LEVEL_NAMES = { 3: 'Easy', 4: 'Medium', 5: 'Normal', 6: 'Hard',
                      7: 'Expert', 8: 'Master', 9: 'Insane' };
const maxGuessesFor = len => Math.min(10, Math.max(4, len + 1));

// ---- state ----------------------------------------------------------------

let level = +(localStorage.getItem('wz_level') || 5);
let soundOn = localStorage.getItem('wz_sound') !== '0';
let target = '', rows = [], cur = '', phase = 'play';   // play|done
let keyState = {};                                      // letter -> class
let me = '';

// ---- sounds (same wavs the desktop plays) ---------------------------------

const SND = {};
function sound(name) {
  if (!soundOn) return;
  try {
    if (!SND[name]) SND[name] = new Audio('/sounds/' + name + '.wav');
    SND[name].currentTime = 0;
    SND[name].play().catch(() => {});
  } catch (e) {}
}
const pick = a => a[Math.floor(Math.random() * a.length)];

// ---- server chatter --------------------------------------------------------

async function api(path, fields) {
  const opt = fields
    ? { method: 'POST', body: new URLSearchParams(fields) }
    : {};
  const r = await fetch(path, opt);
  return r.json().catch(() => ({ ok: false, error: 'the server hiccuped' }));
}

// ---- overlays ---------------------------------------------------------------

function showPane(which) {
  ['join', 'login', 'boardpane'].forEach(p =>
    $(p).classList.toggle('hidden', p !== which));
  $('overlay').classList.toggle('hidden', which === null);
}

async function boot() {
  // words.js only loads once the family cookie is set, so getting here
  // at all means we are in; but the page may be a fresh visitor.
  const r = await api('/api/players');
  if (!r.ok) { showPane('join'); return; }
  const who = document.cookie.match(/(?:^|; )who=([A-Za-z0-9]+)/);
  if (who) { me = who[1]; startPlaying(); }
  else showLogin(r.players);
}

$('joinGo').onclick = async () => {
  const r = await api('/api/join', { pass: $('joinPass').value });
  if (!r.ok) { $('joinErr').textContent = r.error; return; }
  location.reload();       // now /words.js will load
};
$('joinPass').onkeydown = e => { if (e.key === 'Enter') $('joinGo').click(); };

function showLogin(players) {
  showPane('login');
  const n = $('names');
  n.innerHTML = '';
  (players || []).forEach(p => {
    const b = document.createElement('button');
    b.textContent = p;
    b.onclick = () => {
      [...n.children].forEach(c => c.classList.remove('picked'));
      b.classList.add('picked');
      $('loginName').value = p;
      $('loginPin').focus();
    };
    n.appendChild(b);
  });
}

$('loginGo').onclick = async () => {
  const r = await api('/api/login',
    { name: $('loginName').value, pin: $('loginPin').value });
  if (!r.ok) { $('loginErr').textContent = r.error; return; }
  me = r.name;
  startPlaying();
};
$('loginPin').onkeydown = e => { if (e.key === 'Enter') $('loginGo').click(); };

function startPlaying() {
  $('whoami').textContent = me;
  showPane(null);
  newGame();
}

// ---- leaderboard -------------------------------------------------------------

function fillTable(tbl, rows) {
  tbl.innerHTML = '';
  if (!rows.length) {
    tbl.innerHTML = '<tr><td>Nobody yet - go play!</td></tr>';
    return;
  }
  rows.forEach((r, i) => {
    const tr = document.createElement('tr');
    tr.innerHTML = `<td>${i + 1}. ${r.name}</td><td>${r.points} pts</td>` +
                   `<td>${r.won} won of ${r.played}</td>`;
    tbl.appendChild(tr);
  });
}

function showBoard(board) {
  fillTable($('tblDay'), board.day);
  fillTable($('tblMonth'), board.month);
  showPane('boardpane');
}

$('btnBoard').onclick = async () => {
  const r = await api('/api/board');
  if (r.ok) showBoard(r.board);
};
$('boardClose').onclick = () => {
  showPane(null);
  if (phase === 'done') newGame();
};

// ---- the game -----------------------------------------------------------------

function newGame() {
  target = pick(POOLS[level]);
  rows = [];
  cur = '';
  phase = 'play';
  keyState = {};
  setStatus('');
  buildBoard();
  buildKeys();
}

function buildBoard() {
  const maxg = maxGuessesFor(level);
  const b = $('board');
  b.innerHTML = '';
  // tile size that fits both ways, like ComputeBoardMetrics
  const w = $('boardwrap').clientWidth - 20, h = $('boardwrap').clientHeight - 20;
  const ts = Math.max(24, Math.min(64,
    Math.floor(Math.min(w / level, h / maxg)) - 6));
  b.style.setProperty('--ts', ts + 'px');
  for (let r = 0; r < maxg; r++) {
    const row = document.createElement('div');
    row.className = 'row';
    row.id = 'row' + r;
    for (let c = 0; c < level; c++) {
      const t = document.createElement('div');
      t.className = 'tile';
      row.appendChild(t);
    }
    b.appendChild(row);
  }
  paintRow();
}

function paintRow() {
  const row = $('row' + rows.length);
  if (!row) return;
  [...row.children].forEach((t, i) => {
    t.textContent = cur[i] || '';
    t.classList.toggle('full', !!cur[i]);
    if (cur[i] && i === cur.length - 1) {
      t.classList.remove('pop');
      void t.offsetWidth;
      t.classList.add('pop');
    }
  });
}

function setStatus(msg, cls) {
  const s = $('status');
  s.textContent = msg;
  s.className = cls || '';
}

// Standard two-pass Wordle scoring, same as the desktop.
function judge(guess) {
  const res = Array(level).fill('absent');
  const left = {};
  for (let i = 0; i < level; i++) {
    if (guess[i] === target[i]) res[i] = 'correct';
    else left[target[i]] = (left[target[i]] || 0) + 1;
  }
  for (let i = 0; i < level; i++)
    if (res[i] === 'absent' && left[guess[i]]) {
      res[i] = 'present';
      left[guess[i]]--;
    }
  return res;
}

function typeLetter(ch) {
  if (phase !== 'play' || cur.length >= level) return;
  cur += ch;
  sound('key');
  paintRow();
}

function back() {
  if (phase !== 'play' || !cur) return;
  cur = cur.slice(0, -1);
  sound('back');
  paintRow();
}

function submit() {
  if (phase !== 'play' || cur.length < level) return;
  if (!GUESSES.has(cur)) {
    const row = $('row' + rows.length);
    row.classList.remove('shake');
    void row.offsetWidth;
    row.classList.add('shake');
    setStatus(`"${cur}" is not a word here`, 'warn');
    return;
  }
  sound('enter');
  const guess = cur, res = judge(guess);
  rows.push(guess);
  cur = '';
  const rowEl = $('row' + (rows.length - 1));

  if (POTTY.has(guess)) pottyShow();

  // flip the tiles in turn, then settle the result
  [...rowEl.children].forEach((t, i) => {
    setTimeout(() => {
      t.classList.add('flip');
      setTimeout(() => t.classList.add(res[i]), 240);
    }, i * 160);
  });

  setTimeout(() => {
    res.forEach((r, i) => {
      const ch = guess[i], rank = { absent: 0, present: 1, correct: 2 };
      if (!keyState[ch] || rank[r] > rank[keyState[ch]])
        keyState[ch] = r;
    });
    buildKeys();
    if (guess === target) win(rowEl);
    else if (rows.length >= maxGuessesFor(level)) lose();
    else setStatus('');
  }, level * 160 + 300);
}

function win(rowEl) {
  phase = 'done';
  sound(pick(['win1', 'win2', 'win3']));
  [...rowEl.children].forEach((t, i) =>
    setTimeout(() => t.classList.add('bounce'), i * 90));
  rain(['\u{1F389}', '✨', '\u{1F38A}', '⭐'], 40);
  setStatus(`\u{1F389} Solved "${target}" in ${rows.length}!`, 'good');
  report(true);
}

function lose() {
  phase = 'done';
  sound(pick(['lose1', 'lose2', 'lose3', 'poop1', 'poop2']));
  rain(['\u{1F4A9}'], 50);
  setStatus(`\u{1F4A9} Out of tries! It was "${target}"`, 'warn');
  report(false);
}

async function report(won) {
  const r = await api('/api/score', {
    len: level, maxg: maxGuessesFor(level), used: rows.length,
    won: won ? 1 : 0
  });
  if (r.ok) setTimeout(() => showBoard(r.board), 1600);
}

// ---- the potty show (pocket edition) ----------------------------------------

function pottyShow() {
  sound(pick(['fart1', 'fart2', 'fart3']));
  setTimeout(() => sound('flush'), 900);
  rain(['\u{1F4A9}', '\u{1F4A8}', '\u{1F9FB}', '\u{1F6BD}'], 30);
  const b = $('board');
  b.parentElement.classList.remove('quake');
  void b.offsetWidth;
  $('row' + rows.length)?.classList.add('quake');
}

function rain(glyphs, n) {
  for (let i = 0; i < n; i++) {
    const d = document.createElement('div');
    d.className = 'drop';
    d.textContent = pick(glyphs);
    d.style.left = Math.random() * 100 + 'vw';
    d.style.animationDuration = (1.4 + Math.random() * 1.6) + 's';
    d.style.animationDelay = (Math.random() * 0.8) + 's';
    document.body.appendChild(d);
    setTimeout(() => d.remove(), 4200);
  }
}

// ---- keyboard: staggered block, BACK and ENTER in their own column -----------

function buildKeys() {
  const k = $('keys');
  k.innerHTML = '';
  const letters = document.createElement('div');
  letters.id = 'letters';
  ['QWERTYUIOP', 'ASDFGHJKL', 'ZXCVBNM'].forEach(rowStr => {
    const kr = document.createElement('div');
    kr.className = 'krow';
    [...rowStr].forEach(ch => {
      const b = document.createElement('button');
      b.className = 'key' + (keyState[ch] === 'absent' ? ' dead'
        : keyState[ch] ? ' ' + keyState[ch] : '');
      b.textContent = ch;
      b.onclick = () => typeLetter(ch);
      kr.appendChild(b);
    });
    letters.appendChild(kr);
  });
  const sp = document.createElement('div');
  sp.id = 'specials';
  const bb = document.createElement('button');
  bb.className = 'key';
  bb.innerHTML = '&#9003;';
  bb.onclick = back;
  const eb = document.createElement('button');
  eb.className = 'key';
  eb.textContent = 'ENTER';
  eb.onclick = submit;
  sp.appendChild(bb);
  sp.appendChild(eb);
  k.appendChild(letters);
  k.appendChild(sp);
}

// ---- top bar ------------------------------------------------------------------

$('btnNew').onclick = () => { if (confirmAbandon()) newGame(); };
function confirmAbandon() {
  return phase !== 'play' || rows.length === 0 || confirm('Give up this one?');
}

$('btnLevel').onclick = () => {
  const m = $('levelmenu');
  if (!m.classList.contains('hidden')) { m.classList.add('hidden'); return; }
  m.innerHTML = '';
  for (let len = 3; len <= 9; len++) {
    const d = document.createElement('div');
    d.textContent = `${LEVEL_NAMES[len]} · ${len} letters · ` +
                    `${maxGuessesFor(len)} tries`;
    if (len === level) d.className = 'on';
    d.onclick = () => {
      m.classList.add('hidden');
      if (!confirmAbandon()) return;
      level = len;
      localStorage.setItem('wz_level', level);
      newGame();
    };
    m.appendChild(d);
  }
  m.classList.remove('hidden');
};
document.addEventListener('click', e => {
  if (!$('levelmenu').contains(e.target) && e.target !== $('btnLevel'))
    $('levelmenu').classList.add('hidden');
});

$('btnSound').onclick = () => {
  soundOn = !soundOn;
  localStorage.setItem('wz_sound', soundOn ? '1' : '0');
  $('btnSound').textContent = soundOn ? '\u{1F50A}' : '\u{1F507}';
};

// physical keyboard
document.addEventListener('keydown', e => {
  if (!$('overlay').classList.contains('hidden')) return;
  if (e.key === 'Enter') submit();
  else if (e.key === 'Backspace') back();
  else if (/^[a-zA-Z]$/.test(e.key)) typeLetter(e.key.toUpperCase());
});

window.addEventListener('resize', () => { if (target) buildBoard() });

// resize wipes the letters off the board, so repaint what is known
const origBuildBoard = buildBoard;
buildBoard = function () {
  origBuildBoard();
  rows.forEach((g, r) => {
    const res = judge(g), row = $('row' + r);
    [...row.children].forEach((t, i) => {
      t.textContent = g[i];
      t.classList.add('full', res[i]);
    });
  });
  paintRow();
};

boot();
