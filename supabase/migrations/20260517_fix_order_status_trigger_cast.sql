-- Fix auto_post_order_status_message: ELSE branch returned order_status enum,
-- causing PostgreSQL to coerce all text literals (e.g. 'معيّن') to order_status,
-- which fails with error 22P02. Explicit ::text cast resolves the type conflict.
CREATE OR REPLACE FUNCTION public.auto_post_order_status_message()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_entity_name TEXT;
  v_ar_status   TEXT;
BEGIN
  IF OLD.status IS DISTINCT FROM NEW.status THEN
    SELECT name INTO v_entity_name FROM entities WHERE id = NEW.entity_id;

    v_ar_status := CASE NEW.status
      WHEN 'assigned'            THEN 'معيّن'
      WHEN 'picked_up'           THEN 'تم الاستلام'
      WHEN 'on_the_move'         THEN 'في الطريق'
      WHEN 'delivered'           THEN 'تم التسليم'
      WHEN 'delivered_to_storage' THEN 'تم الاستلام في المخزن'
      ELSE NEW.status::text
    END;

    INSERT INTO chat_messages (
      id, thread_id, sender_id, sender_name, content,
      order_mention_id, message_type, created_at
    )
    SELECT
      gen_random_uuid(),
      cm.thread_id,
      NULL,
      'النظام',
      'تغيّرت حالة طلب ' || COALESCE(v_entity_name, '') || ' إلى: ' || v_ar_status,
      NEW.id,
      'system',
      now()
    FROM (
      SELECT DISTINCT cm2.thread_id
      FROM   chat_messages cm2
      JOIN   chat_threads  ct ON ct.id = cm2.thread_id
      WHERE  cm2.order_mention_id = NEW.id
        AND  cm2.message_type     = 'user'
        AND  ct.system_messages_enabled = TRUE
    ) cm;
  END IF;
  RETURN NEW;
END;
$function$;
