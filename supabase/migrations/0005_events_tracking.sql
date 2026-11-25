-- Mesure d'audience : rattacher une partie au compte du joueur connecté (facultatif),
-- et lui permettre de relire ses propres événements (écran « Mes jeux »).

alter table public.events
  add column if not exists user_id uuid references auth.users(id) on delete cascade;

create index if not exists events_user_idx
  on public.events (user_id, game_id, created_at desc)
  where user_id is not null;

-- Envoi : anonyme, ou rattaché uniquement à soi-même.
drop policy if exists "events: envoi" on public.events;
create policy "events: envoi" on public.events
  for insert to anon, authenticated
  with check (
    created_at > now() - interval '1 minute'
    and (user_id is null or user_id = (select auth.uid()))
  );

-- Lecture : l'admin voit tout, un joueur ne voit que ses propres événements.
drop policy if exists "events: admin" on public.events;
drop policy if exists "events: lecture" on public.events;
create policy "events: lecture" on public.events
  for select to authenticated
  using ((select private.is_admin()) or user_id = (select auth.uid()));

-- Les rôles de l'API n'ont pas besoin de ces droits.
revoke truncate, references, trigger on all tables in schema public from anon, authenticated;
