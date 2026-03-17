const MAX_ENTRIES = 100;
const cache = new Map<string, { text: string; durationMs: number }>();

function makeKey(text: string, provider: string, model: string, tone: string, language: string): string {
  return `${provider}:${model}:${tone}:${language}:${text}`;
}

export function getCached(
  text: string,
  provider: string,
  model: string,
  tone: string,
  language: string,
): { text: string; durationMs: number } | null {
  return cache.get(makeKey(text, provider, model, tone, language)) ?? null;
}

export function putCache(
  text: string,
  provider: string,
  model: string,
  tone: string,
  language: string,
  result: { text: string; durationMs: number },
): void {
  const key = makeKey(text, provider, model, tone, language);
  if (cache.size >= MAX_ENTRIES) {
    // Delete oldest entry (first key in Map iteration order)
    const firstKey = cache.keys().next().value;
    if (firstKey) cache.delete(firstKey);
  }
  cache.set(key, result);
}

export function clearCache(): void {
  cache.clear();
}
