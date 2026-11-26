-- Classements : un score par joueur et par jeu, calculé automatiquement depuis la sauvegarde en ligne.
-- NTD : record d'or en une descente (sauvegardes en mode test exclues). Slime Vertical : meilleure hauteur.
create table if not exists public.scores (
  user_id uuid not null references public.profiles(id) on delete cascade,
  game_id text not null references public.games(id) on delete cascade,
  score numeric not null check (score > 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, game_id)
);
create index if not exists scores_board_idx on public.scores (game_id, score desc);

alter table public.scores enable row level security;
drop policy if exists "scores: lecture publique" on public.scores;
create policy "scores: lecture publique" on public.scores for select to anon, authenticated using (true);
drop policy if exists "scores: suppression admin" on public.scores;
create policy "scores: suppression admin" on public.scores for delete to authenticated using ((select private.is_admin()));
revoke all on public.scores from anon, authenticated;
grant select on public.scores to anon, authenticated;
grant delete on public.scores to authenticated;

create or replace function private.sync_score()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  sc numeric;
  d jsonb;
begin
  if tg_op = 'DELETE' then
    delete from public.scores where user_id = old.user_id and game_id = old.game_id;
    return old;
  end if;
  d := new.data;
  sc := case new.game_id
    when 'ntd' then
      case when coalesce(d->'M'->>'test', '0') in ('1', 'true') then null
           when jsonb_typeof(d->'record') = 'number' then floor((d->>'record')::numeric)
           else null end
    when 'slime' then
      case when jsonb_typeof(d->'best') = 'number' then round((d->>'best')::numeric, 1) else null end
    else null
  end;
  -- valeurs impossibles ignorées
  if sc is not null and (sc <= 0 or (new.game_id = 'ntd' and sc > 1000000) or (new.game_id = 'slime' and sc > 100000)) then
    sc := null;
  end if;
  if sc is null then
    delete from public.scores where user_id = new.user_id and game_id = new.game_id;
  else
    insert into public.scores (user_id, game_id, score, updated_at)
    values (new.user_id, new.game_id, sc, now())
    on conflict (user_id, game_id) do update
      set score = excluded.score,
          updated_at = case when public.scores.score is distinct from excluded.score then now() else public.scores.updated_at end;
  end if;
  return new;
end;
$$;
revoke execute on function private.sync_score() from public, anon, authenticated;

drop trigger if exists saves_score on public.saves;
create trigger saves_score after insert or update or delete on public.saves
  for each row execute function private.sync_score();

-- scores des sauvegardes déjà présentes
update public.saves set data = data;
