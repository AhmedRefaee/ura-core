// Always uses the singular unit noun regardless of count (ثانية/دقيقة/ساعة),
// matching the real Flutter app's own duration display exactly — it does
// not do full Arabic numeral-agreement pluralization either.
export function formatDuration(totalSeconds: number): string {
  if (totalSeconds < 1) return 'أقل من ثانية';

  const seconds = Math.floor(totalSeconds);
  if (seconds < 60) return `${seconds} ثانية`;

  if (seconds < 3600) {
    const minutes = Math.floor(seconds / 60);
    const remainingSeconds = seconds % 60;
    return remainingSeconds > 0 ? `${minutes} دقيقة ${remainingSeconds} ثانية` : `${minutes} دقيقة`;
  }

  const hours = Math.floor(seconds / 3600);
  const remainingMinutes = Math.floor((seconds % 3600) / 60);
  return remainingMinutes > 0 ? `${hours} ساعة ${remainingMinutes} دقيقة` : `${hours} ساعة`;
}

export function durationBetween(startIso: string | null, endIso: string | null): string | null {
  if (!startIso || !endIso) return null;
  const start = new Date(startIso).getTime();
  const end = new Date(endIso).getTime();
  if (Number.isNaN(start) || Number.isNaN(end)) return null;
  return formatDuration((end - start) / 1000);
}
