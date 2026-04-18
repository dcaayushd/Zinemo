import type { Router } from 'express';

type HttpMethod = 'get' | 'post' | 'put' | 'patch' | 'delete';

export type MockResponse = {
  statusCode: number;
  body: unknown;
  status: (code: number) => MockResponse;
  json: (payload: unknown) => MockResponse;
};

export function createMockResponse(): MockResponse {
  return {
    statusCode: 200,
    body: undefined,
    status(code: number) {
      this.statusCode = code;
      return this;
    },
    json(payload: unknown) {
      this.body = payload;
      return this;
    },
  };
}

export function getRouteHandler(
  router: Router,
  method: HttpMethod,
  path: string,
): (req: Record<string, unknown>, res: MockResponse) => Promise<void> {
  const layer = (router as unknown as { stack: Array<Record<string, unknown>> }).stack.find(
    (entry) => {
      const route = entry.route as
        | { path?: string; methods?: Record<string, boolean>; stack?: Array<{ handle: unknown }> }
        | undefined;
      if (!route) {
        return false;
      }
      return route.path === path && route.methods?.[method] === true;
    },
  ) as
    | {
        route?: {
          stack?: Array<{ handle: unknown }>;
        };
      }
    | undefined;

  if (!layer?.route?.stack || layer.route.stack.length === 0) {
    throw new Error(`Route ${method.toUpperCase()} ${path} not found`);
  }

  // Use the final route handler and skip auth middleware in tests.
  const handle = layer.route.stack[layer.route.stack.length - 1]?.handle;
  if (typeof handle !== 'function') {
    throw new Error(`Route handler for ${method.toUpperCase()} ${path} is invalid`);
  }

  return handle as (req: Record<string, unknown>, res: MockResponse) => Promise<void>;
}
