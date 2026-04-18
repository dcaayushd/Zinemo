import { redisClient } from './redis';
const MAX_ENTRIES = 500;
const DEFAULT_TTL_SECONDS = 60 * 5;
const memoryCache = new Map();
function pruneMemoryCache() {
    while (memoryCache.size > MAX_ENTRIES) {
        const firstKey = memoryCache.keys().next().value;
        if (!firstKey) {
            return;
        }
        memoryCache.delete(firstKey);
    }
}
function getMemoryValue(key) {
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
    return JSON.parse(entry.value);
}
function setMemoryValue(key, value, ttlSeconds) {
    memoryCache.set(key, {
        value: JSON.stringify(value),
        expiresAt: Date.now() + ttlSeconds * 1000,
    });
    pruneMemoryCache();
}
export async function getCached(key, loader, ttlSeconds = DEFAULT_TTL_SECONDS) {
    const memoryValue = getMemoryValue(key);
    if (memoryValue !== null) {
        return memoryValue;
    }
    if (redisClient) {
        try {
            const redisValue = await redisClient.get(key);
            if (redisValue) {
                const parsed = JSON.parse(redisValue);
                setMemoryValue(key, parsed, ttlSeconds);
                return parsed;
            }
        }
        catch (error) {
            console.warn('Redis cache read failed:', error);
        }
    }
    const fresh = await loader();
    setMemoryValue(key, fresh, ttlSeconds);
    if (redisClient) {
        try {
            await redisClient.set(key, JSON.stringify(fresh), 'EX', ttlSeconds);
        }
        catch (error) {
            console.warn('Redis cache write failed:', error);
        }
    }
    return fresh;
}
