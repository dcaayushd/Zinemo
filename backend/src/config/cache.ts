import { redisClient } from './redis';

type CacheEntry = {
  value: string;
  expiresAt: number;
};

const MAX_ENTRIES = 500;
const DEFAULT_TTL_SECONDS = 60 * 5;
const memoryCache = new Map<string, CacheEntry>();

function pruneMemoryCache(): void {
  while (memoryCache.size > MAX_ENTRIES) {
    const firstKey = memoryCache.keys().next().value as string | undefined;
    if (!firstKey) {
      return;
    }
    memoryCache.delete(firstKey);
  }
}

function getMemoryValue<T>(key: string): T | null {
  const entry = memoryCache.get(key);
  if (!entry) {
    return null;
  }

  if (entry.expiresAt < Date.now()) {
    memoryCache.delete(key);
    return null;
  }

  memoryCache.delete(key);
  memoryCache.set(key, entry);
  return JSON.parse(entry.value) as T;
}

function setMemoryValue<T>(key: string, value: T, ttlSeconds: number): void {
  memoryCache.set(key, {
    value: JSON.stringify(value),
    expiresAt: Date.now() + ttlSeconds * 1000,
  });
  pruneMemoryCache();
}

export async function getCached<T>(
  key: string,
  loader: () => Promise<T>,
  ttlSeconds: number = DEFAULT_TTL_SECONDS,
): Promise<T> {
  const memoryValue = getMemoryValue<T>(key);
  if (memoryValue !== null) {
    return memoryValue;
  }

  if (redisClient) {
    try {
      const redisValue = await redisClient.get(key);
      if (redisValue) {
        const parsed = JSON.parse(redisValue) as T;
        setMemoryValue(key, parsed, ttlSeconds);
        return parsed;
      }
    } catch (error) {
      console.warn('Redis cache read failed:', error);
    }
  }

  const fresh = await loader();
  setMemoryValue(key, fresh, ttlSeconds);

  if (redisClient) {
    try {
      await redisClient.set(key, JSON.stringify(fresh), 'EX', ttlSeconds);
    } catch (error) {
      console.warn('Redis cache write failed:', error);
    }
  }

  return fresh;
}
