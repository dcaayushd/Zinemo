import Redis from 'ioredis';

let redisClient: Redis | null = null;

if (process.env.REDIS_URL) {
  try {
    redisClient = new Redis(process.env.REDIS_URL, {
      maxRetriesPerRequest: null,
      enableReadyCheck: false,
      lazyConnect: true,
    });

    redisClient.on('error', (error) => {
      console.warn('Redis connection warning:', error.message);
    });

    void redisClient.connect().catch((error) => {
      console.warn('Redis unavailable, falling back to in-memory cache:', error.message);
      redisClient = null;
    });
  } catch (error) {
    console.warn('Failed to initialize Redis client:', error);
    redisClient = null;
  }
}

export { redisClient };
