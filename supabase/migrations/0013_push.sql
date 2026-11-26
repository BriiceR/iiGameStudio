-- Notifications web push (appliquée via MCP ; les valeurs des secrets ne sont PAS dans le dépôt).
-- pg_net + pg_cron ; secrets vapid_public, vapid_private, push_cron_secret dans le coffre (vault.create_secret) ;
-- public.push_config() (service_role uniquement) ; règles RLS « push: les miens », « topics: les miens » ;
-- tâche pg_cron « rappel-du-soir » ('0 18,19 * * *') qui appelle la fonction daily-push (elle n'envoie qu'à 20 h, heure de Paris).
create extension if not exists pg_net;
create extension if not exists pg_cron;
create or replace function public.push_config()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'public', (select decrypted_secret from vault.decrypted_secrets where name = 'vapid_public'),
    'private', (select decrypted_secret from vault.decrypted_secrets where name = 'vapid_private'),
    'cron', (select decrypted_secret from vault.decrypted_secrets where name = 'push_cron_secret'));
$$;
revoke execute on function public.push_config() from public, anon, authenticated;
grant execute on function public.push_config() to service_role;
create unique index if not exists push_subscriptions_endpoint_key on public.push_subscriptions (endpoint);
drop policy if exists "push: les miens" on public.push_subscriptions;
create policy "push: les miens" on public.push_subscriptions for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
grant select, insert, update, delete on public.push_subscriptions to authenticated;
create unique index if not exists subscription_topics_key on public.subscription_topics (subscription_id, scope, topic);
drop policy if exists "topics: les miens" on public.subscription_topics;
create policy "topics: les miens" on public.subscription_topics for all to authenticated
  using (exists (select 1 from public.push_subscriptions p where p.id = subscription_id and p.user_id = (select auth.uid())))
  with check (exists (select 1 from public.push_subscriptions p where p.id = subscription_id and p.user_id = (select auth.uid())));
grant select, insert, delete on public.subscription_topics to authenticated;
