/* iiGameStudio : mesure d'audience anonyme, sans cookie.
   Store : <script src="/track.js" defer></script>
   Jeu   : <script src="/track.js" defer data-game="ntd"></script>
   Envoie dans la table events : visit (store, 1 par session d'onglet), launch (chaque ouverture d'un jeu),
   session_end (temps de jeu visible), install (premier lancement de l'appli installée).
   Aucun identifiant durable : la session est un numéro au hasard gardé le temps de l'onglet.
   Si le joueur est connecté, la partie est rattachée à son compte (écran « Mes jeux »). */
(function () {
  if (location.hostname !== 'iigamestudio.vercel.app') return;
  if (navigator.webdriver) return;

  var API = 'https://jadmpivrytjqcdnqtxik.supabase.co/rest/v1/events';
  var KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImphZG1waXZyeXRqcWNkbnF0eGlrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTU1NTAwNTgsImV4cCI6MjExMTEyNjA1OH0.iajubDq4JD36Ojfkk11JF-ec1OE8sFrBSBqy67aMS1k';
  var AUTH = 'sb-jadmpivrytjqcdnqtxik-auth-token';
  var me = document.currentScript;
  var game = (me && me.dataset.game) || null;

  function uuid() {
    if (window.crypto && crypto.randomUUID) return crypto.randomUUID();
    var b = new Uint8Array(16); crypto.getRandomValues(b);
    b[6] = (b[6] & 15) | 64; b[8] = (b[8] & 63) | 128;
    var h = Array.prototype.map.call(b, function (x) { return (x + 256).toString(16).slice(1); }).join('');
    return h.slice(0, 8) + '-' + h.slice(8, 12) + '-' + h.slice(12, 16) + '-' + h.slice(16, 20) + '-' + h.slice(20);
  }
  function ss(k, v) { try { if (v === undefined) return sessionStorage.getItem(k); sessionStorage.setItem(k, v); } catch (e) { return null; } }
  function ls(k, v) { try { if (v === undefined) return localStorage.getItem(k); localStorage.setItem(k, v); } catch (e) { return null; } }

  var sid = ss('iig-sid'); if (!sid) { sid = uuid(); ss('iig-sid', sid); }
  var standalone = matchMedia('(display-mode: standalone)').matches || navigator.standalone === true;
  var ua = navigator.userAgent;
  var os = /iPhone|iPad|iPod/.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1) ? 'ios'
         : /Android/.test(ua) ? 'android' : 'ordi';
  var platform = os + (standalone ? '-app' : '-web');

  function session() {
    try {
      var s = JSON.parse(localStorage.getItem(AUTH) || 'null');
      if (s && s.access_token && s.user && s.expires_at * 1000 > Date.now() + 30000) return s;
    } catch (e) {}
    return null;
  }

  function send(type, extra, anon) {
    var s = anon ? null : session();
    var row = { type: type, game_id: game, session_id: sid, platform: platform };
    if (s) row.user_id = s.user.id;
    for (var k in extra) row[k] = extra[k];
    var p;
    try {
      p = fetch(API, {
        method: 'POST', keepalive: true,
        headers: { apikey: KEY, Authorization: 'Bearer ' + (s ? s.access_token : KEY), 'Content-Type': 'application/json', Prefer: 'return=minimal' },
        body: JSON.stringify(row)
      });
    } catch (e) { return; }
    p.then(function (r) { if (!r.ok && s && (r.status === 401 || r.status === 403)) send(type, extra, true); }, function () {});
  }

  // Visite du store : une fois par session d'onglet. Ouverture d'un jeu : à chaque chargement.
  if (!game) { if (!ss('iig-visit')) { ss('iig-visit', '1'); send('visit', {}); } }
  else send('launch', {});

  // Installation : premier lancement de l'appli installée (store ou jeu).
  var instKey = 'iig-installed-' + (game || 'store');
  // Un jeu ouvert depuis l'appli du store n'est pas une installation du jeu.
  var inStore = game && (/[?&]store=1/.test(location.search) || ss('iig-store') === '1');
  if (standalone && !inStore && !ls(instKey)) { ls(instKey, '1'); send('install', {}); }

  // Temps de jeu : seulement pour les jeux, en comptant le temps où la page est visible.
  if (game) {
    var since = document.visibilityState === 'visible' ? Date.now() : 0;
    var flush = function () {
      if (!since) return;
      var s = Math.round((Date.now() - since) / 1000); since = 0;
      if (s >= 3) send('session_end', { duration_s: Math.min(s, 86400) });
    };
    document.addEventListener('visibilitychange', function () {
      if (document.visibilityState === 'hidden') flush(); else since = Date.now();
    });
    addEventListener('pagehide', flush);
  }
})();
