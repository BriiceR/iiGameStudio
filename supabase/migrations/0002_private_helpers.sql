-- Les fonctions internes passent dans un schéma non exposé par l'API.
create schema if not exists private;
grant usage on schema private to anon, authenticated;

alter function public.is_admin() set schema private;
alter function public.handle_new_user() set schema private;

revoke execute on function private.handle_new_user() from public, anon, authenticated;
revoke execute on function private.is_admin() from public;
grant execute on function private.is_admin() to anon, authenticated;

create or replace function public.protect_review_status()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if tg_op = 'INSERT' and new.status <> 'visible' and not private.is_admin() then
    raise exception 'Un nouvel avis est toujours visible';
  end if;
  if tg_op = 'UPDATE' then
    if new.status is distinct from old.status and not private.is_admin() then
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
revoke execute on function public.protect_review_status() from public, anon, authenticated;
