import { describe, it, expect } from 'vitest';
import { formatDate, formatDateTime, formatTime, formatDateOnly } from './formatDate';

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

describe('formatTime', () => {
  it('returns an em dash for a missing timestamp', () => {
    expect(formatTime(null)).toBe('—');
  });

  it('includes seconds but not the date', () => {
    const a = formatTime('2026-09-28T10:00:00Z');
    const b = formatTime('2026-09-28T10:00:15Z');
    expect(a).not.toBe(b);
    expect(a).not.toContain('2026');
  });
});

describe('formatDateOnly', () => {
  it('returns an em dash for a missing timestamp', () => {
    expect(formatDateOnly(null)).toBe('—');
  });

  it('formats the date without a time component', () => {
    const result = formatDateOnly('2026-09-28T10:00:00Z');
    expect(result).not.toBe('—');
    expect(result).not.toMatch(/\d{2}:\d{2}/);
  });
});
