-- Classements réservés aux membres : seuls les comptes connectés lisent les scores.
drop policy if exists "scores: lecture publique" on public.scores;
drop policy if exists "scores: lecture membres" on public.scores;
create policy "scores: lecture membres" on public.scores for select to authenticated using (true);
revoke select on public.scores from anon;
