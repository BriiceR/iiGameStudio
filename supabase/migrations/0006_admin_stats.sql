-- Tableau de bord admin : chiffres agrégés et liste des joueurs.
-- security invoker : les requêtes passent par les règles RLS de l'admin connecté.
-- Les sessions où un admin était connecté sont exclues des chiffres d'audience.

create or replace function public.admin_stats(p_period text default '7d', p_me boolean default false)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  tz constant text := 'Europe/Paris';
  today date := (now() at time zone tz)::date;
  d_start timestamptz;
  d_prev timestamptz;
  hourly boolean := p_period = 'today';
  res jsonb;
begin
  if not (select private.is_admin()) then
    raise exception 'réservé à l''admin' using errcode = '42501';
  end if;

  d_start := case p_period
    when 'today' then today::timestamp at time zone tz
    when '30d'   then (today - 29)::timestamp at time zone tz
    else              (today - 6)::timestamp at time zone tz
  end;
  d_prev := d_start - (now() - d_start);

  with admins as (
    select id from public.profiles where role = 'admin'
  ),
  adm_sessions as (
    select distinct session_id from public.events where not p_me and user_id in (select id from admins) and created_at >= d_prev
  ),
  ev as (
    select e.* from public.events e
    where e.created_at >= d_prev
      and e.session_id not in (select session_id from adm_sessions)
  ),
  cur as (select * from ev where created_at >= d_start),
  prv as (select * from ev where created_at < d_start),
  buckets as (
    select b as t0
    from generate_series(
      case when hourly then date_trunc('hour', d_start at time zone tz) else (d_start at time zone tz) end,
      date_trunc(case when hourly then 'hour' else 'day' end, now() at time zone tz),
      case when hourly then interval '1 hour' else interval '1 day' end
    ) b
  ),
  series as (
    select jsonb_agg(jsonb_build_object(
      't', to_char(b.t0, case when hourly then 'HH24' else 'YYYY-MM-DD' end),
      'ntd',   (select count(*) from cur where type = 'launch' and game_id = 'ntd'
                 and date_trunc(case when hourly then 'hour' else 'day' end, created_at at time zone tz) = b.t0),
      'slime', (select count(*) from cur where type = 'launch' and game_id = 'slime'
                 and date_trunc(case when hourly then 'hour' else 'day' end, created_at at time zone tz) = b.t0)
    ) order by b.t0) s
    from buckets b
  ),
  per_game as (
    select jsonb_agg(jsonb_build_object(
      'id', g.id,
      'launches', (select count(*) from cur where type = 'launch' and game_id = g.id),
      'players',  (select count(distinct session_id) from cur where type = 'launch' and game_id = g.id),
      'installs', (select count(*) from cur where type = 'install' and game_id = g.id),
      'play_s',   (select coalesce(sum(duration_s), 0) from cur where type = 'session_end' and game_id = g.id),
      'reviews',  (select count(*) from public.reviews r where r.game_id = g.id and r.status = 'visible'),
      'rating',   (select round(avg(rating)::numeric, 1) from public.reviews r where r.game_id = g.id and r.status = 'visible')
    ) order by g.sort_order) j
    from public.games g
    where g.status <> 'cache'
  ),
  recent as (
    select jsonb_agg(x order by x->>'created_at' desc) j from (
      select jsonb_build_object(
        'id', p.id, 'name', p.display_name, 'created_at', p.created_at, 'role', p.role
      ) x
      from public.profiles p order by p.created_at desc limit 5
    ) t
  )
  select jsonb_build_object(
    'period', p_period,
    'since', d_start,
    'visits',        (select count(distinct session_id) from cur),
    'visits_prev',   (select count(distinct session_id) from prv),
    'launches',      (select count(*) from cur where type = 'launch'),
    'launches_prev', (select count(*) from prv where type = 'launch'),
    'play_s',        (select coalesce(sum(duration_s), 0) from cur where type = 'session_end'),
    'installs',      (select count(*) from cur where type = 'install'),
    'players',       (select count(distinct user_id) from cur where user_id is not null),
    'with_me',       p_me,
    'new_accounts',  (select count(*) from public.profiles where created_at >= d_start and role <> 'admin'),
    'accounts',      (select count(*) from public.profiles where role <> 'admin'),
    'new_reviews',   (select count(*) from public.reviews where created_at >= d_start),
    'new_rating',    (select round(avg(rating)::numeric, 1) from public.reviews where created_at >= d_start),
    'reported',      (select count(distinct review_id) from public.review_reports),
    'series',        coalesce((select s from series), '[]'::jsonb),
    'games',         coalesce((select j from per_game), '[]'::jsonb),
    'recent',        coalesce((select j from recent), '[]'::jsonb)
  ) into res;

  return res;
end;
$$;

create or replace function public.admin_players()
returns table (id uuid, name text, role text, created_at timestamptz, last_seen timestamptz, launches bigint, reviews bigint)
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  if not (select private.is_admin()) then
    raise exception 'réservé à l''admin' using errcode = '42501';
  end if;
  return query
    select p.id, p.display_name, p.role, p.created_at,
      (select max(e.created_at) from public.events e where e.user_id = p.id),
      (select count(*) from public.events e where e.user_id = p.id and e.type = 'launch'),
      (select count(*) from public.reviews r where r.user_id = p.id)
    from public.profiles p
    order by p.created_at desc
    limit 500;
end;
$$;

revoke execute on function public.admin_stats(text, boolean) from public, anon;
revoke execute on function public.admin_players() from public, anon;
grant execute on function public.admin_stats(text, boolean) to authenticated;
grant execute on function public.admin_players() to authenticated;
