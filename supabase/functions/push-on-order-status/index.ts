const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const FCM_PROJECT_ID = Deno.env.get('FCM_PROJECT_ID')!;

const DB_HEADERS = {
  'Content-Type': 'application/json',
  'apikey': SUPABASE_KEY,
  'Authorization': `Bearer ${SUPABASE_KEY}`,
};

interface ServiceAccount { client_email: string; private_key: string; }

Deno.serve(async (req: Request) => {
  let payload: any;
  try { payload = await req.json(); }
  catch { return json({ error: 'invalid json' }); }

  const type: string = payload.type ?? 'UPDATE';
  const record = payload.record ?? {};
  const { id: orderId, status, created_by, rep_id, storage_actor_id, entity_id, organization_id } = record;

  if (!orderId) return json({ sent: 0, reason: 'no order id' });

  // Fetch entity name, the order's own org's storage actors (INSERT only), and
  // existing notification history in parallel. Without the org filter a new
  // order pushed to every storage actor of every organization.
  const [entityRes, storageRes, existingRes] = await Promise.all([
    fetch(`${SUPABASE_URL}/rest/v1/entities?select=name&id=eq.${entity_id}`, { headers: DB_HEADERS }),
    type === 'INSERT' && organization_id
      ? fetch(`${SUPABASE_URL}/rest/v1/profiles?select=id&role=eq.storage_actor&is_approved=eq.true&organization_id=eq.${organization_id}`, { headers: DB_HEADERS })
      : Promise.resolve(null),
    fetch(`${SUPABASE_URL}/rest/v1/notifications?select=body&action_route=eq./order/${orderId}&limit=1`, { headers: DB_HEADERS }),
  ]);

  const [entities, storageActors, existingNotifs]: [
    { name: string }[],
    { id: string }[],
    { body: string }[],
  ] = await Promise.all([
    entityRes.json(),
    storageRes ? storageRes.json() : Promise.resolve([]),
    existingRes.json(),
  ]);

  // Build deduplicated participant list
  const base = [created_by, rep_id, storage_actor_id].filter(Boolean) as string[];
  const storageIds: string[] = (storageActors ?? []).map((a: { id: string }) => a.id);
  const participantIds = [...new Set([...base, ...storageIds])];

  if (!participantIds.length) return json({ sent: 0, reason: 'no participants' });

  // FCM tokens for all participants
  const devicesRes = await fetch(
    `${SUPABASE_URL}/rest/v1/user_devices?select=id,fcm_token&user_id=in.(${participantIds.join(',')})`,
    { headers: DB_HEADERS },
  );
  const devices: { id: string; fcm_token: string }[] = await devicesRes.json();
  if (!devices?.length) return json({ sent: 0, reason: 'no devices' });

  const sa: ServiceAccount = JSON.parse(Deno.env.get('FCM_SERVICE_ACCOUNT_JSON')!);
  const accessToken = await getFCMAccessToken(sa);

  const entityName = entities?.[0]?.name ?? 'طلب';
  const latestStatus = statusToArabic(status);
  const previousBody = existingNotifs?.[0]?.body ?? '';

  // Prepend newest status so the first line (collapsed view) always shows the latest
  const accumulatedBody = previousBody
    ? `${latestStatus}\n${previousBody}`
    : latestStatus;

  const title = entityName;
  const notifTag = `order_${orderId}`;
  const actionRoute = `/order/${orderId}`;

  const deadIds: string[] = [];

  const results = await Promise.allSettled(
    devices.map(async (device) => {
      const res = await fetch(
        `https://fcm.googleapis.com/v1/projects/${FCM_PROJECT_ID}/messages:send`,
        {
          method: 'POST',
          headers: { 'Authorization': `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({
            message: {
              token: device.fcm_token,
              // notification.body = latest status only (shown on iOS, web, collapsed Android)
              notification: { title, body: latestStatus },
              data: {
                route: actionRoute,
                // Full history for Flutter foreground BigTextStyle handler
                accumulated_body: accumulatedBody,
              },
              android: {
                priority: 'HIGH',
                notification: {
                  tag: notifTag,
                  // Overrides body on Android: first line = latest (collapsed), all lines = expanded
                  body: accumulatedBody,
                },
              },
              webpush: { notification: { title, body: latestStatus, tag: notifTag } },
            },
          }),
        },
      );
      if (res.status === 404) { deadIds.push(device.id); throw new Error('dead token'); }
      if (!res.ok) throw new Error(`FCM ${res.status}: ${await res.text()}`);
    }),
  );

  // Upsert one notification row per (user, order) with accumulated history as body
  const now = new Date().toISOString();
  await fetch(
    `${SUPABASE_URL}/rest/v1/notifications?on_conflict=user_id%2Caction_route`,
    {
      method: 'POST',
      headers: { ...DB_HEADERS, 'Prefer': 'resolution=merge-duplicates,return=minimal' },
      body: JSON.stringify(
        participantIds.map((uid) => ({
          user_id: uid,
          title,
          body: accumulatedBody,
          action_route: actionRoute,
          is_read: false,
          created_at: now,
        }))
      ),
    },
  ).catch((err) => console.error('Notification upsert failed:', err));

  if (deadIds.length > 0) {
    fetch(
      `${SUPABASE_URL}/rest/v1/user_devices?id=in.(${deadIds.join(',')})`,
      { method: 'DELETE', headers: DB_HEADERS },
    ).catch(() => {});
  }

  const sent = results.filter((r) => r.status === 'fulfilled').length;
  return json({ sent, total: devices.length });
});

function statusToArabic(status: string): string {
  const map: Record<string, string> = {
    assigned:            'تم إنشاء طلب جديد',
    picked_up:           'تم استلام الطلب من المستودع',
    on_the_move:         'الطلب في الطريق',
    delivered:           'تم تسليم الطلب بنجاح',
    delivered_to_storage:'تم تسليم الطلب إلى المستودع',
  };
  return map[status] ?? status;
}

async function getFCMAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claim = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now, exp: now + 3600,
  }));
  const sigInput = `${header}.${claim}`;
  const pem = sa.private_key;
  const b64 = pem.replace(/-----[^-]+-----/g, '').replace(/\s/g, '');
  const binary = atob(b64);
  const der = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) der[i] = binary.charCodeAt(i);
  const key = await crypto.subtle.importKey(
    'pkcs8', der.buffer,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign'],
  );
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(sigInput));
  const jwt = `${sigInput}.${b64url(sig)}`;
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });
  const result = await res.json() as { access_token?: string };
  if (!result.access_token) throw new Error(JSON.stringify(result));
  return result.access_token;
}

function b64url(input: string | ArrayBuffer): string {
  const bytes = typeof input === 'string'
    ? new TextEncoder().encode(input)
    : new Uint8Array(input);
  let binary = '';
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
}

function json(body: unknown): Response {
  return new Response(JSON.stringify(body), {
    headers: { 'Content-Type': 'application/json' },
  });
}