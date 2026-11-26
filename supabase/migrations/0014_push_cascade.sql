-- Un compte supprimé emporte les abonnements de ses téléphones.
alter table public.push_subscriptions drop constraint if exists push_subscriptions_user_id_fkey;
alter table public.push_subscriptions add constraint push_subscriptions_user_id_fkey
  foreign key (user_id) references public.profiles(id) on delete cascade;
