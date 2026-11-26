// Rappel du soir : envoie une notification « viens jouer » aux membres abonnés (sujet « rappel »).
// Appelé par pg_cron (en-tête x-cron-secret). Les clés VAPID sont lues dans le coffre via push_config().
import webpush from "npm:web-push@3.6.7";
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

const json = (o: unknown, status = 200) =>
  new Response(JSON.stringify(o), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  const { data: cfg, error: cfgErr } = await sb.rpc("push_config");
  if (cfgErr || !cfg) return json({ error: "config" }, 500);
  if (req.headers.get("x-cron-secret") !== cfg.cron) return json({ error: "forbidden" }, 403);

  const body = await req.json().catch(() => ({}));
  const hour = Number(new Intl.DateTimeFormat("fr-FR", { hour: "2-digit", hour12: false, timeZone: "Europe/Paris" }).format(new Date()));
  if (!body.force && hour !== 20) return json({ skipped: true, parisHour: hour });

  webpush.setVapidDetails("mailto:iigamestudio@gmail.com", cfg.public, cfg.private);

  const { data: subs, error } = await sb
    .from("push_subscriptions")
    .select("id,endpoint,p256dh,auth,subscription_topics!inner(topic)")
    .eq("subscription_topics.topic", "rappel");
  if (error) return json({ error: error.message }, 500);

  const day = Math.floor(Date.now() / 86400000);
  const m = body.title ? { title: body.title, body: body.body || "" } : MESSAGES[day % MESSAGES.length];
  const payload = JSON.stringify({ ...m, url: "/", tag: "rappel" });

  let sent = 0, gone = 0, failed = 0;
  const errors: string[] = [];
  await Promise.all((subs || []).map(async (s) => {
    try {
      await webpush.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, payload, { TTL: 3600, urgency: "normal" });
      sent++;
    } catch (e) {
      const code = (e as { statusCode?: number }).statusCode;
      if (code === 404 || code === 410) { gone++; await sb.from("push_subscriptions").delete().eq("id", s.id); }
      else { failed++; errors.push(String(code || (e as Error).message).slice(0, 120)); }
    }
  }));

  await sb.from("notifications").insert({ scope: "store", topic: "rappel", title: m.title, body: m.body, url: "/", sent_count: sent });
  return json({ sent, gone, failed, errors, total: subs?.length || 0 });
});
