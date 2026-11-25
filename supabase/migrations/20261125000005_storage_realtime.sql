-- Adda: file storage and live updates
-- Users upload into a folder named after their user id: <bucket>/<user id>/<file>.
-- Admins upload room covers into room-covers/admin/ and catalogue art anywhere in their buckets.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('avatars',      'avatars',      true,  5242880,   array['image/jpeg','image/png','image/webp']),
  ('covers',       'covers',       true,  8388608,   array['image/jpeg','image/png','image/webp']),
  ('room-covers',  'room-covers',  true,  8388608,   array['image/jpeg','image/png','image/webp']),
  ('reels',        'reels',        true,  104857600, array['video/mp4','video/webm','video/quicktime','image/jpeg','image/webp']),
  ('voice',        'voice',        false, 5242880,   array['audio/mp4','audio/aac','audio/mpeg','audio/webm','audio/ogg','audio/m4a']),
  ('verification', 'verification', false, 10485760,  array['image/jpeg','image/png','image/webp']),
  ('gifts',        'gifts',        true,  10485760,  array['image/png','image/webp','image/gif','application/json','video/mp4','image/svg+xml']),
  ('banners',      'banners',      true,  8388608,   array['image/jpeg','image/png','image/webp']),
  ('music',        'music',        true,  20971520,  array['audio/mpeg','audio/mp4','audio/aac','image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

-- public buckets are readable by URL; these policies cover listing and writes
create policy "read public media" on storage.objects for select
  using (bucket_id in ('avatars','covers','room-covers','reels','gifts','banners','music'));

create policy "upload own media" on storage.objects for insert to authenticated
  with check (bucket_id in ('avatars','covers','room-covers','reels','voice','verification')
              and (storage.foldername(name))[1] = auth.uid()::text);
create policy "replace own media" on storage.objects for update to authenticated
  using (bucket_id in ('avatars','covers','room-covers','reels','voice') and (storage.foldername(name))[1] = auth.uid()::text);
create policy "delete own media" on storage.objects for delete to authenticated
  using (bucket_id in ('avatars','covers','room-covers','reels','voice') and (storage.foldername(name))[1] = auth.uid()::text);

-- voice notes: any signed-in user with the path can play them (paths are random)
create policy "play voice notes" on storage.objects for select to authenticated using (bucket_id = 'voice');

-- identity documents: only the owner and admins
create policy "read own verification" on storage.objects for select to authenticated
  using (bucket_id = 'verification' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin()));

-- admins manage catalogue art and homepage covers
create policy "admin media" on storage.objects for all to authenticated
  using (bucket_id in ('room-covers','gifts','banners','music','reels','avatars','covers') and public.is_admin())
  with check (bucket_id in ('room-covers','gifts','banners','music') and public.is_admin());

-- live updates the app subscribes to
do $$ begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
end $$;
alter publication supabase_realtime add table public.room_messages, public.room_seats, public.rooms, public.gift_events,
  public.direct_messages, public.calls, public.notifications, public.wallets;
