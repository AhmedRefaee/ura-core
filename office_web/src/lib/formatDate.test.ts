import { describe, it, expect } from 'vitest';
import { formatDate, formatDateTime } from './formatDate';

describe('formatDate', () => {
  it('returns an em dash for a missing timestamp', () => {
    expect(formatDate(null)).toBe('—');
  });

  it('formats a real timestamp to a non-empty string', () => {
    expect(formatDate('2026-09-28T10:00:00Z')).not.toBe('—');
  });
});

describe('formatDateTime', () => {
  it('returns an em dash for a missing timestamp', () => {
    expect(formatDateTime(null)).toBe('—');
  });

  it('includes seconds, unlike formatDate', () => {
    // Two timestamps a few seconds apart must produce different strings --
    // formatDate (no seconds) would collapse them to the same display text.
    const a = formatDateTime('2026-09-28T10:00:00Z');
    const b = formatDateTime('2026-09-28T10:00:15Z');
    expect(a).not.toBe(b);
  });
});
