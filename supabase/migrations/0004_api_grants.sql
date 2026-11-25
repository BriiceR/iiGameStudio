-- Droits d'accès de l'API (les règles RLS filtrent ensuite ligne par ligne).
grant usage on schema public to anon, authenticated;
grant select on public.games to anon, authenticated;
grant insert, update, delete on public.games to authenticated;
grant select on public.profiles to anon, authenticated;
grant select on public.reviews to anon, authenticated;
grant insert, update, delete on public.reviews to authenticated;
grant insert, select, delete on public.review_reports to authenticated;
grant select on public.game_rating_stats to anon, authenticated;
grant insert on public.events to anon, authenticated;
grant select on public.events to authenticated;
grant select on public.push_subscriptions to authenticated;
grant select on public.subscription_topics to authenticated;
grant select, insert, update, delete on public.notifications to authenticated;
grant select, insert on public.admin_actions to authenticated;
grant select, insert, update, delete on public.admin_alert_settings to authenticated;
grant usage on all sequences in schema public to anon, authenticated;
