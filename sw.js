/* Service worker store : le jeu marche hors ligne une fois ouvert. Changer VERSION à chaque mise à jour. */
const VERSION='store-v6';
const SHELL=["/", "/manifest.webmanifest", "/icons/icon-192.png", "/icons/icon-512.png", "/img/logo.svg", "/img/icon-ntd.svg", "/img/icon-slime.svg", "/img/ntd-titre.webp", "/img/ntd-menu.webp", "/img/ntd-carte.webp", "/img/vertical-jeu.webp"];
self.addEventListener('install',e=>{e.waitUntil(caches.open(VERSION).then(c=>c.addAll(SHELL)).then(()=>self.skipWaiting()))});
self.addEventListener('activate',e=>{e.waitUntil(caches.keys().then(ks=>Promise.all(ks.filter(k=>k.startsWith('store-')&&k!==VERSION).map(k=>caches.delete(k)))).then(()=>self.clients.claim()))});
self.addEventListener('fetch',e=>{
  const r=e.request;if(r.method!=='GET')return;
  const u=new URL(r.url);
  // Polices Google : mises en cache au premier passage
  if(u.hostname==='fonts.googleapis.com'||u.hostname==='fonts.gstatic.com'){
    e.respondWith(caches.open('store-fonts').then(c=>c.match(r).then(m=>m||fetch(r).then(res=>{c.put(r,res.clone());return res}))));return;
  }
  if(u.origin!==location.origin||u.pathname.startsWith('/ntd/')||u.pathname.startsWith('/slime/'))return;
  // Pages : réseau d'abord (pour les mises à jour), cache si hors ligne
  if(r.mode==='navigate'){
    e.respondWith(fetch(r).then(res=>{const c=res.clone();caches.open(VERSION).then(x=>x.put(r,c));return res}).catch(()=>caches.match(r).then(m=>m||caches.match('/'))));return;
  }
  // Fichiers : cache d'abord
  e.respondWith(caches.match(r).then(m=>m||fetch(r).then(res=>{if(res.ok){const c=res.clone();caches.open(VERSION).then(x=>x.put(r,c))}return res})));
});
