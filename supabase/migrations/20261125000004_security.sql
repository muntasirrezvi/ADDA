-- Adda: row level security. The app talks to the database with the user's own token,
-- so these rules are what stop one user from reading or changing another's data.

do $$ declare t text; begin
  foreach t in array array['profiles','profile_private','wallets','transactions','app_settings','coin_packs','payments','gifts',
    'rooms','room_seats','room_members','room_messages','gift_events','room_follows','room_events','event_rsvps','user_follows',
    'blocks','reports','direct_messages','calls','music_tracks','reels','reel_likes','reel_comments','notifications','devices',
    'banners','agencies','hosts','verifications','payouts','agent_stock','agent_sales','daily_checkins','audit_log',
    'room_cover_templates','room_themes','user_themes'] loop
    execute format('alter table public.%I enable row level security', t);
    -- start from nothing; grant back only what each table needs
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant all on public.%I to service_role', t);
  end loop;
end $$;
grant usage on schema public to anon, authenticated, service_role;

-- ---------- catalogues anyone can read ----------
grant select on public.app_settings, public.coin_packs, public.gifts, public.music_tracks, public.banners,
                public.room_cover_templates, public.room_themes to anon, authenticated;
create policy settings_read on public.app_settings for select using (true);
create policy packs_read on public.coin_packs for select using (active or public.is_admin());
create policy gifts_read on public.gifts for select using (active or public.is_admin());
create policy tracks_read on public.music_tracks for select using (active or public.is_admin());
create policy banners_read on public.banners for select using (active or public.is_admin());
create policy templates_read on public.room_cover_templates for select using (active or public.is_admin());
create policy themes_read on public.room_themes for select using (active or public.is_admin());

-- the admin panel edits these catalogues directly (admins only)
grant insert, update, delete on public.coin_packs, public.gifts, public.music_tracks, public.banners,
                public.room_cover_templates, public.room_themes, public.agencies, public.hosts to authenticated;
create policy packs_admin on public.coin_packs for all to authenticated using (public.is_super_admin()) with check (public.is_super_admin());
create policy gifts_admin on public.gifts for all to authenticated using (public.is_super_admin()) with check (public.is_super_admin());
create policy tracks_admin on public.music_tracks for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy banners_admin on public.banners for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy templates_admin on public.room_cover_templates for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy themes_admin on public.room_themes for all to authenticated using (public.is_super_admin()) with check (public.is_super_admin());
grant usage on all sequences in schema public to authenticated;

-- ---------- profiles ----------
grant select on public.profiles to authenticated;
grant update (username, avatar_url, avatar_preset, cover_url, cover_preset, bio, country) on public.profiles to authenticated;
create policy profiles_read on public.profiles for select to authenticated using (deleted_at is null or id = auth.uid() or public.is_admin());
create policy profiles_update_own on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

grant select on public.profile_private to authenticated;
create policy private_read on public.profile_private for select to authenticated using (user_id = auth.uid() or public.is_admin());

-- ---------- money: read your own, never write ----------
grant select on public.wallets, public.transactions, public.payments, public.payouts, public.daily_checkins,
                public.agent_stock, public.agent_sales, public.verifications, public.user_themes to authenticated;
create policy wallets_read on public.wallets for select to authenticated using (user_id = auth.uid() or public.is_admin());
create policy tx_read on public.transactions for select to authenticated using (user_id = auth.uid() or public.is_admin());
create policy payments_read on public.payments for select to authenticated using (user_id = auth.uid() or public.is_admin());
create policy payouts_read on public.payouts for select to authenticated using (user_id = auth.uid() or public.is_admin());
create policy checkins_read on public.daily_checkins for select to authenticated using (user_id = auth.uid());
create policy stock_read on public.agent_stock for select to authenticated using (agent_id = auth.uid() or public.is_admin());
create policy sales_read on public.agent_sales for select to authenticated using (agent_id = auth.uid() or buyer_id = auth.uid() or public.is_admin());
create policy verif_read on public.verifications for select to authenticated using (user_id = auth.uid() or public.is_admin());
create policy user_themes_read on public.user_themes for select to authenticated using (user_id = auth.uid() or public.is_admin());

-- ---------- rooms ----------
-- password_hash is never readable
grant select (id, owner_id, name, topic, language, region, announcement, cover_url, cover_template, theme, seats, locked,
              featured, home_order, status, listeners, score_today, created_at) on public.rooms to authenticated;
-- owners edit name, cover and look; featured / order / status only through admin_update_room
grant update (name, topic, language, region, announcement, cover_url, cover_template, theme) on public.rooms to authenticated;
create policy rooms_read on public.rooms for select to authenticated using (status = 'open' or owner_id = auth.uid() or public.is_admin());
create policy rooms_update_owner on public.rooms for update to authenticated
  using (owner_id = auth.uid() and status <> 'suspended') with check (owner_id = auth.uid());

grant select on public.room_seats, public.room_members, public.gift_events to authenticated;
create policy seats_read on public.room_seats for select to authenticated using (true);
create policy members_read on public.room_members for select to authenticated using (true);
create policy gift_events_read on public.gift_events for select to authenticated using (true);

grant select, insert, delete on public.room_messages to authenticated;
create policy msgs_read on public.room_messages for select to authenticated using (
  exists (select 1 from public.room_members m where m.room_id = room_messages.room_id and m.user_id = auth.uid() and m.role <> 'banned')
  or public.is_admin());
create policy msgs_send on public.room_messages for insert to authenticated with check (
  user_id = auth.uid() and kind in ('text','voice') and public.active_user(auth.uid())
  and exists (select 1 from public.room_members m where m.room_id = room_messages.room_id and m.user_id = auth.uid() and m.role <> 'banned'));
create policy msgs_delete on public.room_messages for delete to authenticated using (user_id = auth.uid() or public.is_room_admin(room_id));

grant select, insert, delete on public.room_follows, public.event_rsvps, public.user_follows to authenticated;
create policy room_follows_read on public.room_follows for select to authenticated using (true);
create policy room_follows_write on public.room_follows for insert to authenticated with check (user_id = auth.uid());
create policy room_follows_del on public.room_follows for delete to authenticated using (user_id = auth.uid());
create policy rsvps_read on public.event_rsvps for select to authenticated using (true);
create policy rsvps_write on public.event_rsvps for insert to authenticated with check (user_id = auth.uid());
create policy rsvps_del on public.event_rsvps for delete to authenticated using (user_id = auth.uid());
create policy follows_read on public.user_follows for select to authenticated using (true);
create policy follows_write on public.user_follows for insert to authenticated with check (follower_id = auth.uid());
create policy follows_del on public.user_follows for delete to authenticated using (follower_id = auth.uid());

grant select, insert, delete on public.room_events to authenticated;
create policy events_read on public.room_events for select to authenticated using (true);
create policy events_write on public.room_events for insert to authenticated with check (created_by = auth.uid() and public.is_room_admin(room_id) and starts_at > now());
create policy events_del on public.room_events for delete to authenticated using (public.is_room_admin(room_id));

-- ---------- safety ----------
grant select, insert, delete on public.blocks to authenticated;
create policy blocks_own on public.blocks for select to authenticated using (blocker_id = auth.uid());
create policy blocks_add on public.blocks for insert to authenticated with check (blocker_id = auth.uid());
create policy blocks_del on public.blocks for delete to authenticated using (blocker_id = auth.uid());

grant select, insert on public.reports to authenticated;
create policy reports_add on public.reports for insert to authenticated with check (reporter_id = auth.uid() and status = 'new');
create policy reports_read on public.reports for select to authenticated using (reporter_id = auth.uid() or public.is_admin());

-- ---------- inbox and calls ----------
grant select, insert on public.direct_messages to authenticated;
grant update (read_at) on public.direct_messages to authenticated;
create policy dm_read on public.direct_messages for select to authenticated using (auth.uid() in (sender_id, receiver_id));
create policy dm_send on public.direct_messages for insert to authenticated with check (
  sender_id = auth.uid() and kind in ('text','voice') and public.active_user(auth.uid())
  and not exists (select 1 from public.blocks b where (b.blocker_id = receiver_id and b.blocked_id = auth.uid())
                                                 or (b.blocker_id = auth.uid() and b.blocked_id = receiver_id)));
create policy dm_mark_read on public.direct_messages for update to authenticated using (receiver_id = auth.uid()) with check (receiver_id = auth.uid());

grant select on public.calls to authenticated;
create policy calls_read on public.calls for select to authenticated using (auth.uid() in (caller_id, callee_id));

-- ---------- reels ----------
grant select, insert, delete on public.reels to authenticated;
grant update (caption, allow_donations, status) on public.reels to authenticated;
create policy reels_read on public.reels for select to authenticated using (status = 'active' or user_id = auth.uid() or public.is_admin());
create policy reels_add on public.reels for insert to authenticated with check (
  user_id = auth.uid() and public.active_user(auth.uid()) and status = 'active' and views = 0 and likes = 0 and comments = 0 and coins_earned = 0
  and video_url ~ ('/storage/v1/object/public/reels/' || auth.uid()::text || '/'));
create policy reels_update_own on public.reels for update to authenticated
  using (user_id = auth.uid() and status <> 'removed') with check (user_id = auth.uid() and status in ('active','hidden'));
create policy reels_admin on public.reels for update to authenticated using (public.is_admin()) with check (true);
create policy reels_del on public.reels for delete to authenticated using (user_id = auth.uid() or public.is_admin());

grant select on public.reel_likes to authenticated;
create policy likes_read on public.reel_likes for select to authenticated using (true);

grant select, insert, delete on public.reel_comments to authenticated;
create policy rc_read on public.reel_comments for select to authenticated using (true);
create policy rc_add on public.reel_comments for insert to authenticated with check (user_id = auth.uid() and public.active_user(auth.uid()));
create policy rc_del on public.reel_comments for delete to authenticated using (
  user_id = auth.uid() or public.is_admin() or exists (select 1 from public.reels r where r.id = reel_id and r.user_id = auth.uid()));
create trigger reel_comments_clean before insert on public.reel_comments for each row execute function public.clean_message();

-- ---------- notifications and devices ----------
grant select, delete on public.notifications to authenticated;
grant update (read) on public.notifications to authenticated;
create policy notif_read on public.notifications for select to authenticated using (user_id = auth.uid());
create policy notif_mark on public.notifications for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy notif_del on public.notifications for delete to authenticated using (user_id = auth.uid());

grant select, insert, update, delete on public.devices to authenticated;
create policy devices_own on public.devices for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------- hosts / agencies / audit ----------
create policy agencies_read on public.agencies for select to authenticated using (true);
create policy agencies_admin on public.agencies for all to authenticated using (public.is_super_admin()) with check (public.is_super_admin());
create policy hosts_read on public.hosts for select to authenticated using (true);
create policy hosts_admin on public.hosts for all to authenticated using (public.is_super_admin()) with check (public.is_super_admin());
grant select on public.agencies, public.hosts, public.audit_log to authenticated;
create policy audit_read on public.audit_log for select to authenticated using (public.is_admin());

-- admins read reports-related content and rooms of any status through the policies above;
-- every admin write that touches money or users goes through the admin_* functions (audited).
