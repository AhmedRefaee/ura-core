import { describe, it, expect } from 'vitest';
import { formatDuration, durationBetween } from './duration';

describe('formatDuration', () => {
  it('formats sub-minute durations in seconds', () => {
    expect(formatDuration(12)).toBe('12 ثانية');
    expect(formatDuration(42)).toBe('42 ثانية');
  });

  it('formats durations under an hour as minutes plus leftover seconds', () => {
    expect(formatDuration(67)).toBe('1 دقيقة 7 ثانية');
    expect(formatDuration(120)).toBe('2 دقيقة');
  });

  it('formats durations of an hour or more as hours plus leftover minutes', () => {
    expect(formatDuration(3600)).toBe('1 ساعة');
    expect(formatDuration(3900)).toBe('1 ساعة 5 دقيقة');
  });

  it('treats zero or negative as less than a second', () => {
    expect(formatDuration(0)).toBe('أقل من ثانية');
    expect(formatDuration(-5)).toBe('أقل من ثانية');
  });
});

describe('durationBetween', () => {
  it('formats the gap between two ISO timestamps', () => {
    expect(durationBetween('2026-09-28T10:00:00Z', '2026-09-28T10:00:12Z')).toBe('12 ثانية');
  });

  it('returns null when either timestamp is missing', () => {
    expect(durationBetween(null, '2026-09-28T10:00:12Z')).toBeNull();
    expect(durationBetween('2026-09-28T10:00:00Z', null)).toBeNull();
  });
});
