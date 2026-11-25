-- iiGameStudio : base de départ (V2, étape 1)
-- Jeux, profils, avis et signalements, fréquentation, notifications, admin.
-- Toutes les tables ont la sécurité par ligne (RLS) activée.

-- ============================================================
-- Jeux
-- ============================================================
create table public.games (
  id          text primary key check (id ~ '^[a-z0-9-]{2,30}$'),
  name        text not null check (char_length(name) between 1 and 60),
  status      text not null default 'dev' check (status in ('jouable', 'dev', 'cache')),
  sort_order  int  not null default 0,
  created_at  timestamptz not null default now()
);
alter table public.games enable row level security;

insert into public.games (id, name, status, sort_order) values
  ('ntd',   'Nine Tiles Dungeon', 'jouable', 1),
  ('slime', 'Slime Vertical',     'jouable', 2);

-- ============================================================
-- Profils (un par compte Supabase Auth)
-- ============================================================
create table public.profiles (
  id            uuid primary key references auth.users (id) on delete cascade,
  display_name  text not null default 'Joueur' check (char_length(display_name) between 1 and 40),
  role          text not null default 'player' check (role in ('player', 'admin')),
  created_at    timestamptz not null default now()
);
alter table public.profiles enable row level security;

-- Un joueur ne peut changer que son nom d'affichage, jamais son rôle.
revoke update on public.profiles from anon, authenticated;
grant update (display_name) on public.profiles to authenticated;

-- Est-ce que la personne connectée est admin ?
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role = 'admin'
  );
$$;
revoke execute on function public.is_admin() from public;
grant execute on function public.is_admin() to anon, authenticated;

-- Création automatique du profil à l'inscription (sans exposer l'e-mail).
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(nullif(left(trim(new.raw_user_meta_data ->> 'name'), 40), ''), 'Joueur')
  );
  return new;
end;
$$;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ============================================================
-- Avis et signalements
-- ============================================================
create table public.reviews (
  id          uuid primary key default gen_random_uuid(),
  game_id     text not null references public.games (id) on delete cascade,
  user_id     uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  rating      smallint not null check (rating between 1 and 5),
  comment     text not null default '' check (char_length(comment) <= 500),
  status      text not null default 'visible' check (status in ('visible', 'masque')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (game_id, user_id)
);
create index reviews_game_idx on public.reviews (game_id, created_at desc);
create index reviews_user_idx on public.reviews (user_id);
alter table public.reviews enable row level security;

-- Seul un admin peut masquer ou réafficher un avis.
create or replace function public.protect_review_status()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' and new.status <> 'visible' and not public.is_admin() then
    raise exception 'Un nouvel avis est toujours visible';
  end if;
  if tg_op = 'UPDATE' then
    if new.status is distinct from old.status and not public.is_admin() then
      raise exception 'Seul un admin peut changer le statut d''un avis';
    end if;
    if new.user_id is distinct from old.user_id or new.game_id is distinct from old.game_id then
      raise exception 'Le jeu et l''auteur d''un avis ne changent pas';
    end if;
    new.updated_at := now();
  end if;
  return new;
end;
$$;
create trigger reviews_protect
  before insert or update on public.reviews
  for each row execute function public.protect_review_status();

create table public.review_reports (
  id           uuid primary key default gen_random_uuid(),
  review_id    uuid not null references public.reviews (id) on delete cascade,
  reporter_id  uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  reason       text not null default '' check (char_length(reason) <= 300),
  created_at   timestamptz not null default now(),
  unique (review_id, reporter_id)
);
create index review_reports_review_idx on public.review_reports (review_id);
create index review_reports_reporter_idx on public.review_reports (reporter_id);
alter table public.review_reports enable row level security;

-- Moyenne et répartition des notes visibles, par jeu.
create view public.game_rating_stats
with (security_invoker = on) as
select
  game_id,
  count(*)::int                               as reviews_count,
  round(avg(rating)::numeric, 2)              as rating_avg,
  count(*) filter (where rating = 5)::int     as r5,
  count(*) filter (where rating = 4)::int     as r4,
  count(*) filter (where rating = 3)::int     as r3,
  count(*) filter (where rating = 2)::int     as r2,
  count(*) filter (where rating = 1)::int     as r1
from public.reviews
where status = 'visible'
group by game_id;

-- ============================================================
-- Fréquentation (anonyme : pas de compte, juste une session)
-- ============================================================
create table public.events (
  id          bigint generated always as identity primary key,
  game_id     text references public.games (id) on delete set null,  -- vide = le store
  type        text not null check (type in ('visit', 'launch', 'session_end', 'install')),
  session_id  uuid not null,
  duration_s  int check (duration_s between 0 and 86400),
  platform    text check (char_length(platform) <= 20),
  created_at  timestamptz not null default now()
);
create index events_game_time_idx on public.events (game_id, created_at desc);
create index events_time_idx on public.events (created_at desc);
alter table public.events enable row level security;

-- ============================================================
-- Notifications
-- ============================================================
create table public.push_subscriptions (
  id          uuid primary key default gen_random_uuid(),
  endpoint    text not null unique,
  p256dh      text not null,
  auth        text not null,
  user_id     uuid references public.profiles (id) on delete set null,
  created_at  timestamptz not null default now(),
  last_seen   timestamptz not null default now()
);
create index push_subscriptions_user_idx on public.push_subscriptions (user_id);
alter table public.push_subscriptions enable row level security;

-- scope = 'store', 'admin' ou l'id d'un jeu ; topic = 'new', 'defi', 'chapitre'…
create table public.subscription_topics (
  subscription_id  uuid not null references public.push_subscriptions (id) on delete cascade,
  scope            text not null check (char_length(scope) <= 30),
  topic            text not null check (char_length(topic) <= 30),
  primary key (subscription_id, scope, topic)
);
alter table public.subscription_topics enable row level security;

create table public.notifications (
  id          uuid primary key default gen_random_uuid(),
  scope       text not null check (char_length(scope) <= 30),
  topic       text not null check (char_length(topic) <= 30),
  title       text not null check (char_length(title) between 1 and 50),
  body        text not null check (char_length(body) between 1 and 140),
  url         text check (char_length(url) <= 200),
  sent_count  int  not null default 0,
  created_by  uuid default auth.uid() references public.profiles (id) on delete set null,
  created_at  timestamptz not null default now()
);
create index notifications_created_by_idx on public.notifications (created_by);
alter table public.notifications enable row level security;

-- ============================================================
-- Admin : historique et réglages des alertes
-- ============================================================
create table public.admin_actions (
  id          bigint generated always as identity primary key,
  admin_id    uuid default auth.uid() references public.profiles (id) on delete set null,
  action      text not null check (char_length(action) <= 40),
  target      text check (char_length(target) <= 100),
  details     jsonb not null default '{}',
  created_at  timestamptz not null default now()
);
create index admin_actions_admin_idx on public.admin_actions (admin_id);
alter table public.admin_actions enable row level security;

create table public.admin_alert_settings (
  admin_id    uuid primary key references public.profiles (id) on delete cascade,
  settings    jsonb not null default '{}',
  updated_at  timestamptz not null default now()
);
alter table public.admin_alert_settings enable row level security;

-- ============================================================
-- Règles d'accès (RLS)
-- ============================================================

-- Jeux : tout le monde voit les jeux non cachés ; l'admin voit et gère tout.
create policy "games: lecture publique" on public.games
  for select to anon, authenticated
  using (status <> 'cache' or (select public.is_admin()));
create policy "games: gestion admin" on public.games
  for all to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

-- Profils : les noms d'affichage sont publics (pour signer les avis) ; chacun modifie le sien.
create policy "profiles: lecture publique" on public.profiles
  for select to anon, authenticated using (true);
create policy "profiles: modifier le sien" on public.profiles
  for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- Avis : visibles par tous ; l'auteur voit aussi le sien s'il est masqué ; l'admin voit tout.
create policy "reviews: lecture" on public.reviews
  for select to anon, authenticated
  using (status = 'visible' or user_id = (select auth.uid()) or (select public.is_admin()));
create policy "reviews: écrire le sien" on public.reviews
  for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy "reviews: modifier le sien ou admin" on public.reviews
  for update to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()))
  with check (user_id = (select auth.uid()) or (select public.is_admin()));
create policy "reviews: supprimer le sien ou admin" on public.reviews
  for delete to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()));

-- Signalements : un joueur connecté signale ; seul l'admin les lit et les traite.
create policy "reports: signaler" on public.review_reports
  for insert to authenticated
  with check (reporter_id = (select auth.uid()));
create policy "reports: admin" on public.review_reports
  for select to authenticated using ((select public.is_admin()));
create policy "reports: admin supprime" on public.review_reports
  for delete to authenticated using ((select public.is_admin()));

-- Fréquentation : tout le monde peut envoyer un événement ; seul l'admin lit.
create policy "events: envoi" on public.events
  for insert to anon, authenticated
  with check (created_at > now() - interval '1 minute');
create policy "events: admin" on public.events
  for select to authenticated using ((select public.is_admin()));

-- Notifications : abonnements gérés par une fonction serveur ; l'admin lit et envoie.
create policy "push: admin lit" on public.push_subscriptions
  for select to authenticated using ((select public.is_admin()));
create policy "topics: admin lit" on public.subscription_topics
  for select to authenticated using ((select public.is_admin()));
create policy "notifications: admin" on public.notifications
  for all to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

-- Admin : historique et réglages d'alertes réservés aux admins.
create policy "admin_actions: admin" on public.admin_actions
  for all to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));
create policy "alert_settings: admin" on public.admin_alert_settings
  for all to authenticated
  using ((select public.is_admin()) and admin_id = (select auth.uid()))
  with check ((select public.is_admin()) and admin_id = (select auth.uid()));
