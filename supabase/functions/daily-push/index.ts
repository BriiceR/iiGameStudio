// @ts-nocheck
// Rappel du soir : envoie une notification « viens jouer » aux membres abonnés (sujet « rappel »).
// Appelé par pg_cron (en-tête x-cron-secret). Les clés VAPID sont lues dans le coffre via push_config().
// Chiffrement Web Push fait en WebCrypto (RFC 8291, vérifié sur le vecteur de test de la RFC) : pas de dépendance Node.
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});

const MESSAGES = [
  { title: "Le donjon t'attend 🗝️", body: "Neuf cases, un héros, et toi. Viens jouer !" },
  { title: "Le slime s'ennuie 🟦", body: "Il ne montera pas tout seul. Viens jouer !" },
  { title: "C'est l'heure de jouer 🎮", body: "Une petite partie avant de dormir ?" },
  { title: "Ton record t'attend 🏆", body: "Viens voir si tu fais mieux qu'hier." },
  { title: "iiGameStudio 👾", body: "Les jeux du studio qui n'existe pas t'attendent." },
];

// ---- Web Push en WebCrypto
const te = new TextEncoder();
// deno-lint-ignore-file no-explicit-any
const b64u = {
  enc: (b) => { let s = ""; const u = new Uint8Array(b); for (let i = 0; i < u.length; i++) s += String.fromCharCode(u[i]); return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, ""); },
  dec: (s) => { s = s.replace(/-/g, "+").replace(/_/g, "/"); s += "=".repeat((4 - s.length % 4) % 4); const b = atob(s); return Uint8Array.from(b, (c) => c.charCodeAt(0)); },
};
const cat = (...a) => { const n = a.reduce((x, y) => x + y.length, 0), o = new Uint8Array(n); let p = 0; for (const x of a) { o.set(x, p); p += x.length; } return o; };
async function hmac(key, data) { const k = await crypto.subtle.importKey("raw", key, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]); return new Uint8Array(await crypto.subtle.sign("HMAC", k, data)); }
async function hkdf(salt, ikm, info, len) { const prk = await hmac(salt, ikm); const t = await hmac(prk, cat(info, new Uint8Array([1]))); return t.slice(0, len); }
function privJwk(d, pub) { return { kty: "EC", crv: "P-256", d: b64u.enc(d), x: b64u.enc(pub.slice(1, 33)), y: b64u.enc(pub.slice(33, 65)), ext: true }; }

async function encrypt(plaintext, uaPubB64, authB64) {
  const uaPub = b64u.dec(uaPubB64), auth = b64u.dec(authB64);
  const kp = await crypto.subtle.generateKey({ name: "ECDH", namedCurve: "P-256" }, true, ["deriveBits"]);
  const asPriv = kp.privateKey, asPub = new Uint8Array(await crypto.subtle.exportKey("raw", kp.publicKey));
  const uaKey = await crypto.subtle.importKey("raw", uaPub, { name: "ECDH", namedCurve: "P-256" }, false, []);
  const ecdh = new Uint8Array(await crypto.subtle.deriveBits({ name: "ECDH", public: uaKey }, asPriv, 256));
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const ikm = await hkdf(auth, ecdh, cat(te.encode("WebPush: info\0"), uaPub, asPub), 32);
  const cek = await hkdf(salt, ikm, te.encode("Content-Encoding: aes128gcm\0"), 16);
  const nonce = await hkdf(salt, ikm, te.encode("Content-Encoding: nonce\0"), 12);
  const key = await crypto.subtle.importKey("raw", cek, "AES-GCM", false, ["encrypt"]);
  const ct = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv: nonce }, key, cat(te.encode(plaintext), new Uint8Array([2]))));
  const rs = new Uint8Array([0, 0, 16, 0]);
  return cat(salt, rs, new Uint8Array([asPub.length]), asPub, ct);
}

async function vapidHeader(endpoint, pubB64, privB64, subject) {
  const pub = b64u.dec(pubB64);
  const key = await crypto.subtle.importKey("jwk", privJwk(b64u.dec(privB64), pub), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const u = new URL(endpoint);
  const h = b64u.enc(te.encode(JSON.stringify({ typ: "JWT", alg: "ES256" })));
  const c = b64u.enc(te.encode(JSON.stringify({ aud: u.origin, exp: Math.floor(Date.now() / 1000) + 12 * 3600, sub: subject })));
  const sig = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, te.encode(h + "." + c)));
  return `vapid t=${h}.${c}.${b64u.enc(sig)}, k=${pubB64}`;
}

async function sendPush(sub, payload, vapid, opts = {}) {
  const body = payload == null ? undefined : await encrypt(payload, sub.p256dh, sub.auth);
  const headers = { TTL: String(opts.ttl ?? 3600), Urgency: opts.urgency || "normal", Authorization: await vapidHeader(sub.endpoint, vapid.pub, vapid.priv, vapid.subject) };
  if (body) { headers["Content-Encoding"] = "aes128gcm"; headers["Content-Type"] = "application/octet-stream"; }
  const r = await fetch(sub.endpoint, { method: "POST", headers, body });
  return { status: r.status, text: r.ok ? "" : (await r.text()).slice(0, 200) };
}

const json = (o: unknown, status = 200) =>
  new Response(JSON.stringify(o), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  const { data: cfg, error: cfgErr } = await sb.rpc("push_config");
  if (cfgErr || !cfg) return json({ error: "config" }, 500);
  if (req.headers.get("x-cron-secret") !== cfg.cron) return json({ error: "forbidden" }, 403);

  const body = await req.json().catch(() => ({}));
  const hour = Number(new Intl.DateTimeFormat("fr-FR", { hour: "2-digit", hour12: false, timeZone: "Europe/Paris" }).format(new Date()));
  if (!body.force && hour !== 20) return json({ skipped: true, parisHour: hour });

  const vapid = { pub: cfg.public, priv: cfg.private, subject: "mailto:iigamestudio@gmail.com" };

  const { data: subs, error } = await sb
    .from("push_subscriptions")
    .select("id,endpoint,p256dh,auth,subscription_topics!inner(topic)")
    .eq("subscription_topics.topic", "rappel");
  if (error) return json({ error: error.message }, 500);

  const day = Math.floor(Date.now() / 86400000);
  const m = body.title ? { title: body.title, body: body.body || "" } : MESSAGES[day % MESSAGES.length];
  const payload = body.empty ? null : JSON.stringify({ ...m, url: "/", tag: body.title ? "test-" + Date.now() : "rappel-" + day });

  let sent = 0, gone = 0, failed = 0;
  const errors: string[] = [];
  await Promise.all((subs || []).map(async (s) => {
    try {
      const r = await sendPush(s, payload, vapid, { ttl: 3600, urgency: "high" });
      if (r.status >= 200 && r.status < 300) sent++;
      else if (r.status === 404 || r.status === 410) { gone++; await sb.from("push_subscriptions").delete().eq("id", s.id); }
      else { failed++; errors.push((r.status + " " + r.text).slice(0, 160)); }
    } catch (e) { failed++; errors.push(String((e as Error).message).slice(0, 160)); }
  }));

  await sb.from("notifications").insert({ scope: "store", topic: "rappel", title: m.title, body: m.body, url: "/", sent_count: sent });
  return json({ sent, gone, failed, errors, total: subs?.length || 0 });
});
