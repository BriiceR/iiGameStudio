/* Service worker store : le jeu marche hors ligne une fois ouvert. Changer VERSION à chaque mise à jour. */
const VERSION='store-v20';
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
  // Journal des nouveautés : réseau d'abord (il change aussi quand seul un jeu est mis à jour)
  if(u.pathname==='/changelog.json'){
    e.respondWith(fetch(r).then(res=>{if(res.ok){const c=res.clone();caches.open(VERSION).then(x=>x.put(r,c))}return res}).catch(()=>caches.match(r)));return;
  }
  // Fichiers : cache d'abord
  e.respondWith(caches.match(r).then(m=>m||fetch(r).then(res=>{if(res.ok){const c=res.clone();caches.open(VERSION).then(x=>x.put(r,c))}return res})));
});
// Notifications (rappel du soir, annonces) : affichage et ouverture du store au toucher
self.addEventListener('push',e=>{
  let d={};try{d=e.data?e.data.json():{}}catch(_){d={body:e.data&&e.data.text()}}
  e.waitUntil(self.registration.showNotification(d.title||'iiGameStudio',{body:d.body||'',icon:'/icons/icon-192.png',badge:'/icons/icon-192.png',tag:d.tag||('iig-'+Date.now()),renotify:!!d.tag,data:{url:d.url||'/'}}));
});
self.addEventListener('notificationclick',e=>{
  e.notification.close();
  const url=new URL((e.notification.data&&e.notification.data.url)||'/',self.location.origin).href;
  e.waitUntil(clients.matchAll({type:'window',includeUncontrolled:true}).then(ws=>{for(const w of ws){if(w.url.startsWith(self.location.origin)&&'focus' in w){w.navigate(url).catch(()=>{});return w.focus()}}return clients.openWindow(url)}));
});
