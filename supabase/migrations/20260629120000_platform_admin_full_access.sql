-- The platform_admin account has had `is_platform_admin()` correctly defined
-- and referenced in ~15+ RLS policies, but almost everywhere it's nested
-- inside an AND with a role/approval condition (e.g. get_user_role() =
-- 'manager') that assumes the caller has a normal, approved profile in some
-- org. The platform admin has no profiles row, so those conditions always
-- fail and is_platform_admin() is never reached. Fix by adding one new,
-- purely additive permissive policy per affected table — Postgres ORs
-- multiple permissive policies together, so this can only ever grant MORE
-- access (solely to the one account whose JWT carries the claim) and cannot
-- weaken any existing policy for any other user.
--
-- Scoped to exactly the two tables the org/user-management admin console
-- needs directly: organizations, profiles. The new RPCs below are SECURITY
-- DEFINER, so they bypass RLS entirely for their own internal reads/writes
-- and don't need a bypass policy on the other tables they touch.

CREATE POLICY "platform_admin_bypass" ON public.organizations
  FOR ALL USING (public.is_platform_admin()) WITH CHECK (public.is_platform_admin());

CREATE POLICY "platform_admin_bypass" ON public.profiles
  FOR ALL USING (public.is_platform_admin()) WITH CHECK (public.is_platform_admin());


-- Change the role of an already-approved member, in any org. approve_user
-- only handles the pending -> approved transition; this fills the gap for
-- changing role after approval.
CREATE OR REPLACE FUNCTION public.admin_change_member_role(
  p_user_id uuid,
  p_new_role public.user_role
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
begin
  if not is_platform_admin() then
    return jsonb_build_object('success', false, 'error', 'forbidden');
  end if;

  update profiles
  set role = p_new_role
  where id = p_user_id
    and is_approved = true;

  if not found then
    return jsonb_build_object('success', false, 'error', 'approved member not found');
  end if;

  return jsonb_build_object('success', true);
end
$$;

-- Remove/deactivate a member, in any org. Sets is_approved = false rather
-- than deleting the profiles row: profiles.id is referenced by non-cascading
-- FKs from orders/order_items/audit_log/chat_messages/receipts/urgent_notes
-- etc, so a hard delete on a profile that has ever touched an order would
-- fail with a FK violation. Reusing is_approved=false is reversible and
-- immediately hides the member from every existing approved-only view.
-- Known trade-off: a removed member renders identically to a brand-new
-- pending signup in the same org until re-approved or reassigned.
CREATE OR REPLACE FUNCTION public.admin_remove_member(
  p_user_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
begin
  if not is_platform_admin() then
    return jsonb_build_object('success', false, 'error', 'forbidden');
  end if;

  update profiles
  set is_approved = false
  where id = p_user_id;

  if not found then
    return jsonb_build_object('success', false, 'error', 'member not found');
  end if;

  return jsonb_build_object('success', true);
end
$$;

-- Delete an organization, but only if it's genuinely empty. organization_id
-- FKs from profiles/orders/entities/inventory/chat_threads/order_templates
-- don't cascade, so this refuses to delete (rather than silently cascading
-- and destroying real data) whenever any of those tables still has rows for
-- the org.
CREATE OR REPLACE FUNCTION public.admin_delete_organization(
  p_org_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
declare
  v_profiles_count   int;
  v_orders_count     int;
  v_entities_count   int;
  v_inventory_count  int;
  v_chat_count       int;
  v_templates_count  int;
begin
  if not is_platform_admin() then
    return jsonb_build_object('success', false, 'error', 'forbidden');
  end if;

  if not exists (select 1 from organizations where id = p_org_id) then
    return jsonb_build_object('success', false, 'error', 'org not found');
  end if;

  select count(*) into v_profiles_count  from profiles        where organization_id = p_org_id;
  select count(*) into v_orders_count    from orders          where organization_id = p_org_id;
  select count(*) into v_entities_count  from entities        where organization_id = p_org_id;
  select count(*) into v_inventory_count from inventory       where organization_id = p_org_id;
  select count(*) into v_chat_count      from chat_threads    where organization_id = p_org_id;
  select count(*) into v_templates_count from order_templates where organization_id = p_org_id;

  if (v_profiles_count + v_orders_count + v_entities_count
      + v_inventory_count + v_chat_count + v_templates_count) > 0 then
    return jsonb_build_object(
      'success', false,
      'error', 'المؤسسة تحتوي على بيانات ولا يمكن حذفها',
      'counts', jsonb_build_object(
        'profiles', v_profiles_count,
        'orders', v_orders_count,
        'entities', v_entities_count,
        'inventory', v_inventory_count,
        'chat_threads', v_chat_count,
        'order_templates', v_templates_count
      )
    );
  end if;

  delete from organizations where id = p_org_id;

  return jsonb_build_object('success', true);
end
$$;

GRANT ALL ON FUNCTION public.admin_change_member_role(uuid, public.user_role) TO authenticated;
GRANT ALL ON FUNCTION public.admin_change_member_role(uuid, public.user_role) TO service_role;

GRANT ALL ON FUNCTION public.admin_remove_member(uuid) TO authenticated;
GRANT ALL ON FUNCTION public.admin_remove_member(uuid) TO service_role;

GRANT ALL ON FUNCTION public.admin_delete_organization(uuid) TO authenticated;
GRANT ALL ON FUNCTION public.admin_delete_organization(uuid) TO service_role;
