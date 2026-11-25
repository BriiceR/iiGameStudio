-- Une règle par action pour l'admin sur les jeux (évite deux règles de lecture en double).
drop policy "games: gestion admin" on public.games;
create policy "games: ajout admin" on public.games for insert to authenticated with check ((select private.is_admin()));
create policy "games: modif admin" on public.games for update to authenticated using ((select private.is_admin())) with check ((select private.is_admin()));
create policy "games: suppression admin" on public.games for delete to authenticated using ((select private.is_admin()));
