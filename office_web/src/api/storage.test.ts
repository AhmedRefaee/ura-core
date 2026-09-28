import { describe, it, expect, vi } from 'vitest';

describe('resolveSignedUrl', () => {
  it('returns null for a missing path', async () => {
    vi.doMock('../lib/supabase', () => ({ supabase: { storage: { from: vi.fn() } } }));
    vi.resetModules();
    const { resolveSignedUrl } = await import('./storage');
    expect(await resolveSignedUrl('delivery-receipts', null)).toBeNull();
  });

  it('requests a signed URL for a stored path', async () => {
    const createSignedUrl = vi.fn().mockResolvedValue({ data: { signedUrl: 'https://signed.example/x.pdf' }, error: null });
    const from = vi.fn().mockReturnValue({ createSignedUrl });
    vi.doMock('../lib/supabase', () => ({ supabase: { storage: { from } } }));
    vi.resetModules();
    const { resolveSignedUrl } = await import('./storage');

    const url = await resolveSignedUrl('delivery-receipts', 'org1/u1/1.pdf');
    expect(from).toHaveBeenCalledWith('delivery-receipts');
    expect(createSignedUrl).toHaveBeenCalledWith('org1/u1/1.pdf', 3600);
    expect(url).toBe('https://signed.example/x.pdf');
  });

  it('extracts the storage path out of a legacy full public URL', async () => {
    const createSignedUrl = vi.fn().mockResolvedValue({ data: { signedUrl: 'https://signed.example/x.pdf' }, error: null });
    const from = vi.fn().mockReturnValue({ createSignedUrl });
    vi.doMock('../lib/supabase', () => ({ supabase: { storage: { from } } }));
    vi.resetModules();
    const { resolveSignedUrl } = await import('./storage');

    await resolveSignedUrl('delivery-receipts', 'https://x.supabase.co/storage/v1/object/public/delivery-receipts/org1/u1/1.pdf');
    expect(createSignedUrl).toHaveBeenCalledWith('org1/u1/1.pdf', 3600);
  });
});
