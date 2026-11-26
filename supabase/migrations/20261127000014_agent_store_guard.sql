-- Agents can only send from their store to normal users: never to themselves or other agents/admins.
create or replace function public.store_transfer(p_to_public bigint, p_coins bigint, p_diamonds bigint, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); role_ user_role; to_id uuid; c bigint := greatest(coalesce(p_coins, 0), 0); d bigint := greatest(coalesce(p_diamonds, 0), 0); s agent_stock;
begin
  select role into role_ from profiles where id = me;
  if role_ not in ('agent','admin') then raise exception 'only agents can send from a store'; end if;
  if c = 0 and d = 0 then raise exception 'enter an amount'; end if;
  to_id := _public_to_id(p_to_public);
  if to_id = me then raise exception 'you cannot send from your store to yourself'; end if;
  if role_ = 'agent' and exists (select 1 from profiles where id = to_id and role in ('agent','admin')) then
    raise exception 'agents cannot send store coins to other agents or admins';
  end if;
  if role_ = 'agent' then
    update agent_stock set coins = coins - c, diamonds = diamonds - d where agent_id = me and coins >= c and diamonds >= d returning * into s;
    if not found then raise exception 'not enough in your store'; end if;
  end if;
  perform _wallet_add(to_id, c, d, 'store_transfer', me::text, jsonb_build_object('from', me, 'role', role_));
  insert into coin_transfers(from_id, to_id, coins, diamonds, kind, note) values (me, to_id, c, d, case when role_ = 'admin' then 'admin' else 'agent' end, p_note);
  perform _notify(to_id, 'You received ' || concat_ws(' + ', case when c > 0 then c || ' coins' end, case when d > 0 then d || ' diamonds' end),
                  'From ' || (select username from profiles where id = me) || case when role_ = 'agent' then ' (coin agent)' else ' (Adda team)' end,
                  jsonb_build_object('type', 'wallet'));
  return jsonb_build_object('ok', true, 'store_coins', s.coins, 'store_diamonds', s.diamonds);
end $$;
