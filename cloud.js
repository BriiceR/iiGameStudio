/* iiGameStudio : sauvegarde en ligne commune à tous les jeux.
   À charger AVANT le script du jeu :  <script src="/cloud.js"></script>
   API (window.iigCloud) :
     await iigCloud.user()        -> {id, email} ou null (renouvelle la connexion si besoin)
     const d = iigCloud.doc('ntd') -> await d.get() : {exists, data()}  ·  await d.set(objet)
     await iigCloud.login()       -> ouvre une fenêtre de connexion (e-mail + code), true si connecté
   La connexion est la même que celle du store (même stockage du navigateur). */
(function () {
  var API = 'https://jadmpivrytjqcdnqtxik.supabase.co';
  var KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImphZG1waXZyeXRqcWNkbnF0eGlrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTU1NTAwNTgsImV4cCI6MjExMTEyNjA1OH0.iajubDq4JD36Ojfkk11JF-ec1OE8sFrBSBqy67aMS1k';
  var AUTH = 'sb-jadmpivrytjqcdnqtxik-auth-token';
  var refreshing = null;

  function read() { try { return JSON.parse(localStorage.getItem(AUTH) || 'null'); } catch (e) { return null; } }
  function write(s) {
    if (!s.expires_at && s.expires_in) s.expires_at = Math.floor(Date.now() / 1000) + s.expires_in;
    try { localStorage.setItem(AUTH, JSON.stringify(s)); } catch (e) {}
    return s;
  }
  function headers(token, extra) {
    var h = { apikey: KEY, Authorization: 'Bearer ' + (token || KEY), 'Content-Type': 'application/json' };
    for (var k in extra) h[k] = extra[k];
    return h;
  }

  async function session() {
    var s = read();
    if (!s || !s.access_token || !s.user) return null;
    if (s.expires_at * 1000 > Date.now() + 60000) return s;
    if (!s.refresh_token) return null;
    if (!refreshing) {
      refreshing = (async function () {
        try {
          var r = await fetch(API + '/auth/v1/token?grant_type=refresh_token', {
            method: 'POST', headers: headers(null), body: JSON.stringify({ refresh_token: s.refresh_token })
          });
          if (r.ok) return write(await r.json());
          // jeton refusé : la connexion n'est plus valable, sauf si le store vient de la renouveler entre-temps
          var now = read();
          if (now && now.refresh_token !== s.refresh_token && now.expires_at * 1000 > Date.now() + 60000) return now;
          if (r.status === 400 || r.status === 401 || r.status === 403) { try { localStorage.removeItem(AUTH); } catch (e) {} }
          return null;
        } catch (e) { return null; }
        finally { setTimeout(function () { refreshing = null; }, 0); }
      })();
    }
    return refreshing;
  }

  async function user() {
    var s = await session();
    return s ? { id: s.user.id, email: s.user.email } : null;
  }

  function doc(game) {
    return {
      get: async function () {
        var s = await session(); if (!s) throw new Error('non connecté');
        var r = await fetch(API + '/rest/v1/saves?select=data,updated_at&game_id=eq.' + encodeURIComponent(game) + '&user_id=eq.' + s.user.id,
          { headers: headers(s.access_token) });
        if (!r.ok) throw new Error('lecture ' + r.status);
        var rows = await r.json(), row = rows[0];
        return { exists: !!row, updated_at: row && row.updated_at, data: function () { return row ? row.data : null; } };
      },
      set: async function (data) {
        var s = await session(); if (!s) throw new Error('non connecté');
        var r = await fetch(API + '/rest/v1/saves?on_conflict=user_id,game_id', {
          method: 'POST', keepalive: JSON.stringify(data).length < 60000,
          headers: headers(s.access_token, { Prefer: 'resolution=merge-duplicates,return=minimal' }),
          body: JSON.stringify({ user_id: s.user.id, game_id: game, data: data })
        });
        if (!r.ok) throw new Error('écriture ' + r.status);
        return true;
      }
    };
  }

  /* ---------- fenêtre de connexion (e-mail puis code), isolée du style du jeu ---------- */
  function login() {
    return new Promise(function (done) {
      var host = document.createElement('div');
      host.style.cssText = 'position:fixed;inset:0;z-index:2147483600';
      var root = host.attachShadow({ mode: 'open' });
      root.innerHTML = '<style>' +
        ':host{all:initial}*{box-sizing:border-box}' +
        '.bg{position:fixed;inset:0;background:rgba(10,4,16,.78);display:flex;align-items:flex-end;justify-content:center;padding:16px;padding-bottom:max(16px,env(safe-area-inset-bottom));font:16px/1.45 Rubik,system-ui,-apple-system,sans-serif;color:#F5EFFA}' +
        '@media (min-width:600px){.bg{align-items:center}}' +
        '.box{width:100%;max-width:400px;background:#22132E;border:1px solid #3A2A48;border-radius:16px;padding:20px;display:grid;gap:14px;box-shadow:0 20px 60px rgba(0,0,0,.5)}' +
        '.hd{display:flex;align-items:center;gap:12px}.hd svg{width:36px;height:36px;flex:none}' +
        'h2{margin:0;font:400 18px/1.2 Silkscreen,"Courier New",monospace}' +
        'p{margin:0;font-size:14px;color:#A9A0B3}p b{color:#F5EFFA;font-weight:500}' +
        'input{font:inherit;font-size:16px;color:#F5EFFA;background:#140A1C;border:2px solid #3A2A48;border-radius:8px;padding:12px;width:100%}' +
        'input:focus{outline:none;border-color:#C28CE0}input.code{font:400 24px Silkscreen,"Courier New",monospace;letter-spacing:.25em;text-align:center}' +
        'button{font:400 14px Silkscreen,"Courier New",monospace;min-height:48px;border-radius:8px;border:0;cursor:pointer;background:#7E2CA3;color:#fff;width:100%}' +
        'button[disabled]{opacity:.6}button.ghost{background:transparent;color:#F5EFFA;box-shadow:inset 0 0 0 2px #3A2A48}' +
        '.row{display:grid;grid-template-columns:1fr 1fr;gap:8px}.msg{font-size:13px;min-height:1em}.err{color:#FF8FA3}' +
        'label{font-size:13px;color:#A9A0B3;display:block;margin-bottom:6px}' +
        '</style><div class="bg"><form class="box" role="dialog" aria-modal="true" aria-labelledby="t" novalidate></form></div>';
      var form = root.querySelector('form'), step = 'email', email = '', codeVal = '';
      var logo = '<svg viewBox="0 0 500 500" aria-hidden="true"><rect width="500" height="500" rx="48" fill="#7E2CA3"/><path fill="#fff" d="M57 201H112V251H57ZM56 265H111V388H56ZM127 201H182V251H127ZM126 265H181V388H126ZM277 112H444V167H277ZM222 167H277V333H222ZM332 222H444V278H332ZM388 278H444V333H388ZM277 333H388V388H277Z"/></svg>';
      function close(ok) { host.remove(); document.removeEventListener('keydown', esc, true); done(ok); }
      function esc(e) { if (e.key === 'Escape') { e.stopPropagation(); close(false); } }
      function draw(msg, err, busy) {
        form.innerHTML = '<div class="hd">' + logo + '<h2 id="t">' + (step === 'email' ? 'Sauvegarde en ligne' : 'Ton code') + '</h2></div>' +
          (step === 'email'
            ? '<p>Connecte-toi avec ton compte iiGameStudio pour retrouver ta progression sur tous tes appareils. Pas de mot de passe : on t\'envoie un code.</p>' +
              '<div><label for="em">Ton adresse e-mail</label><input id="em" type="email" inputmode="email" autocomplete="email" placeholder="toi@exemple.fr"></div>'
            : '<p>On a envoyé un code à <b></b>. Tape-le ici (regarde dans les spams si besoin).</p>' +
              '<div><label for="cd">Code reçu par e-mail</label><input id="cd" class="code" inputmode="numeric" autocomplete="one-time-code" maxlength="10" placeholder="••••••••"></div>') +
          '<p class="msg' + (err ? ' err' : '') + '" role="status"></p>' +
          '<div class="row"><button type="button" class="ghost" data-x>' + (step === 'email' ? 'PLUS TARD' : 'RETOUR') + '</button><button type="submit"' + (busy ? ' disabled' : '') + '>' +
          (busy ? '…' : step === 'email' ? 'RECEVOIR' : 'VALIDER') + '</button></div>';
        form.querySelector('.msg').textContent = msg || '';
        var b = form.querySelector('p b'); if (b) b.textContent = email;
        var i = form.querySelector('input'); if (i) { i.value = step === 'email' ? email : codeVal; setTimeout(function () { i.focus(); }, 30); }
        form.querySelector('[data-x]').onclick = function () { if (step === 'code') { step = 'email'; codeVal = ''; draw(); } else close(false); };
      }
      form.onsubmit = async function (e) {
        e.preventDefault();
        if (step === 'email') {
          email = (form.querySelector('#em').value || '').trim();
          if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return draw('Cette adresse ne semble pas valide.', true);
          draw('', false, true);
          try {
            var r = await fetch(API + '/auth/v1/otp', { method: 'POST', headers: headers(null), body: JSON.stringify({ email: email, create_user: true }) });
            if (!r.ok) { step = 'email'; return draw(r.status === 429 ? "Trop d'e-mails envoyés : patiente une minute." : "L'envoi n'a pas marché, réessaie.", true); }
            step = 'code'; draw();
          } catch (x) { draw('Pas de connexion internet.', true); }
        } else {
          var code = codeVal = (form.querySelector('#cd').value || '').replace(/\D/g, '');
          if (code.length < 6) return draw('Tape tous les chiffres du code.', true);
          draw('', false, true);
          try {
            var v = await fetch(API + '/auth/v1/verify', { method: 'POST', headers: headers(null), body: JSON.stringify({ type: 'email', email: email, token: code }) });
            if (!v.ok) return draw('Code incorrect ou expiré.', true);
            write(await v.json());
            close(true);
          } catch (x) { draw('Pas de connexion internet.', true); }
        }
      };
      host.addEventListener('click', function (e) { if (e.composedPath()[0] === root.querySelector('.bg')) close(false); });
      document.addEventListener('keydown', esc, true);
      document.body.appendChild(host);
      draw();
    });
  }

  window.iigCloud = { user: user, doc: doc, login: login, session: session };
})();
