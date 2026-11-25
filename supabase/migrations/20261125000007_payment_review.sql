-- Adda: let a super admin approve a payment SSLCommerz held for review, or refund one
create or replace function public.admin_approve_payment(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r jsonb;
begin
  if not is_super_admin() then raise exception 'super admins only'; end if;
  r := complete_payment(p_id, null, (select coalesce(raw, '{}') || jsonb_build_object('approved_by', auth.uid()) from payments where id = p_id));
  perform _audit('approve_payment', p_id::text, r);
  return r;
end $$;

-- marks a paid payment refunded and takes the coins back (as many as are left)
create or replace function public.admin_refund_payment(p_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare p payments; take bigint;
begin
  if not is_super_admin() then raise exception 'super admins only'; end if;
  select * into p from payments where id = p_id and status = 'paid' for update;
  if not found then raise exception 'only paid payments can be refunded'; end if;
  select least(coins, p.coins) into take from wallets where user_id = p.user_id for update;
  if take > 0 then perform _wallet_add(p.user_id, -take, 0, 'refund', p_id::text, jsonb_build_object('reason', p_reason)); end if;
  update payments set status = 'refunded' where id = p_id;
  perform _audit('refund_payment', p_id::text, jsonb_build_object('reason', p_reason, 'coins_taken', take));
  return jsonb_build_object('ok', true, 'coins_taken', take);
end $$;

revoke execute on function public.admin_approve_payment(uuid), public.admin_refund_payment(uuid, text) from public, anon;
grant execute on function public.admin_approve_payment(uuid), public.admin_refund_payment(uuid, text) to authenticated, service_role;
