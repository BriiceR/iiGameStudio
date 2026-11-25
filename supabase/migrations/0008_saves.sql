-- Sauvegarde en ligne : une ligne par joueur et par jeu, contenu libre propre à chaque jeu.
create table if not exists public.saves (
  user_id uuid not null references auth.users(id) on delete cascade,
  game_id text not null references public.games(id) on delete cascade,
  data jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, game_id),
  constraint saves_size check (pg_column_size(data) < 262144)
);

alter table public.saves enable row level security;

create or replace function private.touch_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin new.updated_at := now(); return new; end; $$;

drop trigger if exists saves_touch on public.saves;
create trigger saves_touch before insert or update on public.saves
  for each row execute function private.touch_updated_at();

drop policy if exists "saves: lecture" on public.saves;
create policy "saves: lecture" on public.saves for select to authenticated
  using (user_id = (select auth.uid()) or (select private.is_admin()));
drop policy if exists "saves: ecriture" on public.saves;
create policy "saves: ecriture" on public.saves for insert to authenticated
  with check (user_id = (select auth.uid()));
drop policy if exists "saves: modification" on public.saves;
create policy "saves: modification" on public.saves for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
drop policy if exists "saves: suppression" on public.saves;
create policy "saves: suppression" on public.saves for delete to authenticated
  using (user_id = (select auth.uid()));

revoke all on public.saves from anon;
grant select, insert, update, delete on public.saves to authenticated;
