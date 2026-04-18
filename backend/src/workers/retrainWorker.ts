import { Queue, Worker } from 'bullmq';
import axios from 'axios';
import { Redis } from 'ioredis';

const redisUrl = process.env.REDIS_URL || 'redis://localhost:6379';
const isTestEnvironment = process.env.NODE_ENV === 'test';
const redisConnection = isTestEnvironment
  ? null
  : new Redis(redisUrl, {
      maxRetriesPerRequest: null,
      enableReadyCheck: false,
    });
const ml_service_url = process.env.ML_SERVICE_URL || 'http://localhost:8000';

type RetrainQueueLike = Pick<Queue, 'add'>;

const retrainQueue: RetrainQueueLike = isTestEnvironment
  ? {
      add: async () => ({ id: 'test-job' } as never),
    }
  : new Queue('retrain', { connection: redisConnection! });

// Atomic counter for new logs
export async function onNewLog() {
  if (!redisConnection) {
    return;
  }

  try {
    const count = await redisConnection.incr('zinemo:log_counter');

    // Trigger retrain every 50 new logs
    if (count % 50 === 0) {
      await retrainQueue.add('retrain', { timestamp: Date.now() }, { jobId: `retrain-${count}` });
      console.log(`Retrain job triggered after ${count} logs`);
    }
  } catch (error) {
    console.error('Error incrementing log counter:', error);
  }
}

const shouldStartWorker = !isTestEnvironment && redisConnection !== null;

// Worker to process retrain jobs.
const worker = shouldStartWorker
  ? new Worker(
      'retrain',
      async (job) => {
        console.log('Processing retrain job:', job.id);
        try {
          // Only trigger if running in scratch mode.
          if (process.env.RECOMMENDATION_MODE === 'scratch') {
            await axios.post(
              `${ml_service_url}/train`,
              {},
              { timeout: 30000, headers: { 'Content-Type': 'application/json' } },
            );
            console.log('Model retraining triggered successfully');
          }
        } catch (error) {
          console.warn('Retrain trigger failed (non-fatal):', error);
          // Don't throw, let job succeed even if retrain fails.
        }
      },
      { connection: redisConnection!, concurrency: 1 },
    )
  : null;

if (worker) {
  worker.on('completed', (job) => {
    console.log(`Retrain job ${job.id} completed`);
  });

  worker.on('failed', (job, err) => {
    console.error(`Retrain job ${job?.id} failed:`, err.message);
  });
}

export { retrainQueue };
