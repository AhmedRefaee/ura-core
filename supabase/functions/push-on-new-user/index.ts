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

  const record = payload.record ?? {};
  const { id: newUserId, full_name, is_approved, organization_id } = record;

  if (!newUserId) return json({ sent: 0, reason: 'no user id' });
  // Only fire for new unapproved users (i.e. registration, not profile edits)
  if (is_approved) return json({ sent: 0, reason: 'user already approved' });
  if (!organization_id) return json({ sent: 0, reason: 'no organization' });

  // Fetch the approved managers of the org the user is joining -- not every
  // organization's managers.
  const managersRes = await fetch(
    `${SUPABASE_URL}/rest/v1/profiles?select=id&role=eq.manager&is_approved=eq.true&organization_id=eq.${organization_id}`,
    { headers: DB_HEADERS },
  );
  const managers: { id: string }[] = await managersRes.json();
  if (!managers?.length) return json({ sent: 0, reason: 'no managers found' });

  const managerIds = managers.map((m) => m.id);

  // FCM tokens for all managers
  const devicesRes = await fetch(
    `${SUPABASE_URL}/rest/v1/user_devices?select=id,fcm_token&user_id=in.(${managerIds.join(',')})`,
    { headers: DB_HEADERS },
  );
  const devices: { id: string; fcm_token: string }[] = await devicesRes.json();

  const title = 'طلب انضمام جديد';
  const body = `${full_name ?? 'مستخدم جديد'} ينتظر الموافقة على حسابه`;
  // Unique tag per pending user so each registration has its own notification slot
  const notifTag = `pending_user_${newUserId}`;
  const actionRoute = `/pending-user/${newUserId}`;

  const deadIds: string[] = [];
  let sent = 0;

  if (devices?.length) {
    const sa: ServiceAccount = JSON.parse(Deno.env.get('FCM_SERVICE_ACCOUNT_JSON')!);
    const accessToken = await getFCMAccessToken(sa);

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
                notification: { title, body },
                data: { route: actionRoute },
                android: {
                  priority: 'HIGH',
                  notification: { tag: notifTag },
                },
                webpush: { notification: { title, body, tag: notifTag } },
              },
            }),
          },
        );
        if (res.status === 404) { deadIds.push(device.id); throw new Error('dead token'); }
        if (!res.ok) throw new Error(`FCM ${res.status}: ${await res.text()}`);
      }),
    );
    sent = results.filter((r) => r.status === 'fulfilled').length;
  }

  // Insert one in-app notification per manager (unique per pending user via action_route)
  await fetch(
    `${SUPABASE_URL}/rest/v1/notifications?on_conflict=user_id%2Caction_route`,
    {
      method: 'POST',
      headers: { ...DB_HEADERS, 'Prefer': 'resolution=merge-duplicates,return=minimal' },
      body: JSON.stringify(
        managerIds.map((uid) => ({
          user_id: uid,
          title,
          body,
          action_route: actionRoute,
          is_read: false,
          created_at: new Date().toISOString(),
        }))
      ),
    },
  ).catch((err) => console.error('Notification insert failed:', err));

  if (deadIds.length > 0) {
    fetch(
      `${SUPABASE_URL}/rest/v1/user_devices?id=in.(${deadIds.join(',')})`,
      { method: 'DELETE', headers: DB_HEADERS },
    ).catch(() => {});
  }

  return json({ sent, total: devices?.length ?? 0 });
});

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