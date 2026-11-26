-- Petites protections pour un store d'une vingtaine de joueurs :
-- 1) scores : un bond suspect en une seule sauvegarde est signalé à l'admin (une fois par jour au plus), qui peut retirer le joueur ;
-- 2) l'admin peut retirer un joueur d'un classement (et l'y remettre) ;
-- 3) mesure d'audience : une même session ne peut pas envoyer plus de 60 événements en 10 minutes.

-- 2) joueurs retirés d'un classement
create table if not exists public.score_bans (
  user_id uuid not null references public.profiles(id) on delete cascade,
  game_id text not null references public.games(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, game_id)
);
alter table public.score_bans enable row level security;
drop policy if exists "score_bans: admin" on public.score_bans;
create policy "score_bans: admin" on public.score_bans for all to authenticated
  using ((select private.is_admin())) with check ((select private.is_admin()));
revoke all on public.score_bans from anon, authenticated;
grant select, insert, delete on public.score_bans to authenticated;

-- 1) calcul du score avec garde-fous
create or replace function private.sync_score()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  sc numeric;
  old_sc numeric;
  jump_max numeric;
  d jsonb;
begin
  if tg_op = 'DELETE' then
    delete from public.scores where user_id = old.user_id and game_id = old.game_id;
    return old;
  end if;
  -- joueur retiré de ce classement par l'admin
  if exists (select 1 from public.score_bans b where b.user_id = new.user_id and b.game_id = new.game_id) then
    delete from public.scores where user_id = new.user_id and game_id = new.game_id;
    return new;
  end if;
  d := new.data;
  sc := case new.game_id
    when 'ntd' then
      case when coalesce(d->'M'->>'test', '0') in ('1', 'true') then null
           when jsonb_typeof(d->'M'->'xp') = 'number' then floor((d->'M'->>'xp')::numeric)
           else null end
    when 'slime' then
      case when jsonb_typeof(d->'best') = 'number' then round((d->>'best')::numeric, 1) else null end
    else null
  end;
  if sc is not null and (sc <= 0 or (new.game_id = 'ntd' and sc > 100000000) or (new.game_id = 'slime' and sc > 100000)) then
    sc := null;
  end if;
  if sc is null then
    delete from public.scores where user_id = new.user_id and game_id = new.game_id;
    return new;
  end if;
  -- bond maximal crédible entre deux sauvegardes (une sauvegarde part toutes les quelques secondes de jeu)
  jump_max := case new.game_id when 'ntd' then 5000 when 'slime' then 1500 else null end;
  select s.score into old_sc from public.scores s where s.user_id = new.user_id and s.game_id = new.game_id;
  if jump_max is not null and old_sc is not null and sc - old_sc > jump_max
     and not exists (select 1 from public.admin_actions a where a.action = 'score_suspect'
                     and a.target = 'score:' || new.game_id || ':' || new.user_id and a.created_at > now() - interval '1 day') then
    insert into public.admin_actions (admin_id, action, target, details)
    values (null, 'score_suspect', 'score:' || new.game_id || ':' || new.user_id,
            jsonb_build_object('game', new.game_id, 'user', new.user_id, 'avant', old_sc, 'apres', sc));
  end if;
  insert into public.scores (user_id, game_id, score, updated_at)
  values (new.user_id, new.game_id, sc, now())
  on conflict (user_id, game_id) do update
    set score = excluded.score,
        updated_at = case when public.scores.score is distinct from excluded.score then now() else public.scores.updated_at end;
  return new;
end;
$$;
revoke execute on function private.sync_score() from public, anon, authenticated;

-- 3) limite d'envoi pour la mesure d'audience
create index if not exists events_session_time_idx on public.events (session_id, created_at desc);
create or replace function private.events_rate_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select count(*) from public.events e
      where e.session_id = new.session_id and e.created_at > now() - interval '10 minutes') >= 60 then
    return null; -- ignoré sans erreur
  end if;
  return new;
end;
$$;
revoke execute on function private.events_rate_limit() from public, anon, authenticated;
drop trigger if exists events_rate on public.events;
create trigger events_rate before insert on public.events
  for each row execute function private.events_rate_limit();
