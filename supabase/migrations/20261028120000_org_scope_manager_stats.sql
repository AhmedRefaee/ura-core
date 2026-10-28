-- The manager stats screen counted every tenant's orders.
--
-- get_global_stats_overview, get_orders_monthly_summary and
-- get_rep_performance_stats are SECURITY DEFINER, so RLS never applied to
-- them, and none of them filtered by organization. A manager therefore saw
-- totals across ALL organizations, and the rep-performance list named every
-- approved rep in the system. All three were also executable by anon, so the
-- same data was readable with just the public anon key.
--
-- Each now reads only the caller's organization. auth_org_id() is NULL for
-- anon and for the platform admin (who has no org and doesn't use this
-- screen), so they get empty results: fail closed.
--
-- Signatures are unchanged, so CREATE OR REPLACE keeps the existing grants;
-- anon and PUBLIC are then revoked.

CREATE OR REPLACE FUNCTION "public"."get_global_stats_overview"("p_start" timestamp with time zone DEFAULT ("now"() - '30 days'::interval), "p_end" timestamp with time zone DEFAULT "now"()) RETURNS json
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT JSON_BUILD_OBJECT(
    'total_orders',     COUNT(*),
    'delivered_orders', COUNT(*) FILTER (WHERE status = 'delivered'),
    'active_orders',    COUNT(*) FILTER (WHERE status != 'delivered'),
    'outbound_count',   COUNT(*) FILTER (WHERE direction = 'outbound'),
    'inbound_count',    COUNT(*) FILTER (WHERE direction != 'outbound'),
    'avg_total_hours',  ROUND(AVG(
      EXTRACT(EPOCH FROM (delivered_at - created_at)) / 3600
    ) FILTER (WHERE delivered_at IS NOT NULL), 1)
  )
  FROM orders
  WHERE created_at BETWEEN p_start AND p_end
    AND organization_id = auth_org_id();
$$;

CREATE OR REPLACE FUNCTION "public"."get_orders_monthly_summary"("p_start" timestamp with time zone DEFAULT ("now"() - '1 year'::interval), "p_end" timestamp with time zone DEFAULT "now"()) RETURNS TABLE("month" "text", "total_orders" bigint, "delivered_orders" bigint, "outbound_orders" bigint, "inbound_orders" bigint)
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT
    TO_CHAR(DATE_TRUNC('month', created_at), 'YYYY-MM'),
    COUNT(*),
    COUNT(*) FILTER (WHERE status = 'delivered'),
    COUNT(*) FILTER (WHERE direction = 'outbound'),
    COUNT(*) FILTER (WHERE direction != 'outbound')
  FROM orders
  WHERE created_at BETWEEN p_start AND p_end
    AND organization_id = auth_org_id()
  GROUP BY DATE_TRUNC('month', created_at)
  ORDER BY DATE_TRUNC('month', created_at);
$$;

CREATE OR REPLACE FUNCTION "public"."get_rep_performance_stats"("p_start" timestamp with time zone DEFAULT ("now"() - '30 days'::interval), "p_end" timestamp with time zone DEFAULT "now"()) RETURNS TABLE("rep_id" "uuid", "rep_name" "text", "total_orders" bigint, "delivered_orders" bigint, "avg_hours_to_pickup" numeric, "avg_hours_in_transit" numeric, "avg_total_hours" numeric)
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT
    p.id,
    p.full_name,
    COUNT(o.id),
    COUNT(o.id) FILTER (WHERE o.status = 'delivered'),
    ROUND(AVG(
      EXTRACT(EPOCH FROM (o.picked_up_at - o.assigned_at)) / 3600
    ) FILTER (WHERE o.picked_up_at IS NOT NULL AND o.assigned_at IS NOT NULL), 1),
    ROUND(AVG(
      EXTRACT(EPOCH FROM (o.delivered_at - o.picked_up_at)) / 3600
    ) FILTER (WHERE o.delivered_at IS NOT NULL AND o.picked_up_at IS NOT NULL), 1),
    ROUND(AVG(
      EXTRACT(EPOCH FROM (o.delivered_at - o.created_at)) / 3600
    ) FILTER (WHERE o.delivered_at IS NOT NULL), 1)
  FROM profiles p
  LEFT JOIN orders o
    ON o.rep_id = p.id
   AND o.organization_id = p.organization_id
   AND o.created_at BETWEEN p_start AND p_end
  WHERE p.role = 'rep' AND p.is_approved = true
    AND p.organization_id = auth_org_id()
  GROUP BY p.id, p.full_name
  ORDER BY COUNT(o.id) DESC;
$$;

REVOKE EXECUTE ON FUNCTION "public"."get_global_stats_overview"(timestamp with time zone, timestamp with time zone) FROM "anon", PUBLIC;
REVOKE EXECUTE ON FUNCTION "public"."get_orders_monthly_summary"(timestamp with time zone, timestamp with time zone) FROM "anon", PUBLIC;
REVOKE EXECUTE ON FUNCTION "public"."get_rep_performance_stats"(timestamp with time zone, timestamp with time zone) FROM "anon", PUBLIC;
GRANT EXECUTE ON FUNCTION "public"."get_global_stats_overview"(timestamp with time zone, timestamp with time zone) TO "authenticated";
GRANT EXECUTE ON FUNCTION "public"."get_orders_monthly_summary"(timestamp with time zone, timestamp with time zone) TO "authenticated";
GRANT EXECUTE ON FUNCTION "public"."get_rep_performance_stats"(timestamp with time zone, timestamp with time zone) TO "authenticated";
