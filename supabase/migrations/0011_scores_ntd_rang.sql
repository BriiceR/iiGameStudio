-- Classement NTD : au rang du joueur (expérience totale M.xp) au lieu du record d'or.
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

-- recalcul des scores NTD existants
update public.saves set data = data where game_id = 'ntd';
