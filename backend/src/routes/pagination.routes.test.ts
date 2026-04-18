import logsRouter from './logs';
import listsRouter from './lists';
import * as supabaseConfig from '../config/supabase';
import { createMockResponse, getRouteHandler } from '../testUtils/routerTestUtils';

type MockQuery<T> = {
  data: T[];
  error: null;
  count: number;
  select: jest.Mock;
  eq: jest.Mock;
  order: jest.Mock;
  lt: jest.Mock;
  limit: jest.Mock;
  range: jest.Mock;
};

function createMockQuery<T>(rows: T[], count: number = rows.length): MockQuery<T> {
  const query = {
    data: rows,
    error: null,
    count,
    select: jest.fn(() => query),
    eq: jest.fn(() => query),
    order: jest.fn(() => query),
    lt: jest.fn(() => query),
    limit: jest.fn(() => query),
    range: jest.fn(() => query),
  } as unknown as MockQuery<T>;

  return query;
}

describe('Cursor pagination endpoints', () => {
  afterEach(() => {
    jest.restoreAllMocks();
  });

  it('uses cursor pagination in logs endpoint when cursor is provided', async () => {
    const rows = [
      { id: 'log-1', created_at: '2026-04-16T10:00:00.000Z' },
      { id: 'log-2', created_at: '2026-04-15T10:00:00.000Z' },
    ];
    const query = createMockQuery(rows);

    jest.spyOn(supabaseConfig, 'requireSupabase').mockReturnValue({
      from: () => query,
    } as never);

    const handler = getRouteHandler(logsRouter, 'get', '/');
    const res = createMockResponse();

    await handler(
      {
        user: { id: 'user-1' },
        query: {
          cursor: '2026-04-16T11:00:00.000Z',
          limit: '2',
        },
      },
      res,
    );

    expect(query.lt).toHaveBeenCalledWith('created_at', '2026-04-16T11:00:00.000Z');
    expect(query.limit).toHaveBeenCalledWith(2);
    expect(query.range).not.toHaveBeenCalled();
    expect(res.statusCode).toBe(200);
    expect(res.body).toMatchObject({
      limit: 2,
      cursor: '2026-04-16T11:00:00.000Z',
      nextCursor: '2026-04-15T10:00:00.000Z',
    });
  });

  it('keeps offset pagination fallback in logs endpoint', async () => {
    const rows = [{ id: 'log-11', created_at: '2026-04-01T10:00:00.000Z' }];
    const query = createMockQuery(rows, 42);

    jest.spyOn(supabaseConfig, 'requireSupabase').mockReturnValue({
      from: () => query,
    } as never);

    const handler = getRouteHandler(logsRouter, 'get', '/');
    const res = createMockResponse();

    await handler(
      {
        user: { id: 'user-1' },
        query: {
          offset: '5',
          limit: '2',
        },
      },
      res,
    );

    expect(query.range).toHaveBeenCalledWith(5, 6);
    expect(query.lt).not.toHaveBeenCalled();
    expect(res.statusCode).toBe(200);
    expect(res.body).toMatchObject({
      limit: 2,
      offset: 5,
      count: 42,
    });
  });

  it('uses cursor pagination in lists endpoint when cursor is provided', async () => {
    const rows = [
      { id: 'list-1', created_at: '2026-04-16T09:00:00.000Z' },
      { id: 'list-2', created_at: '2026-04-14T09:00:00.000Z' },
    ];
    const query = createMockQuery(rows);

    jest.spyOn(supabaseConfig, 'requireSupabase').mockReturnValue({
      from: () => query,
    } as never);

    const handler = getRouteHandler(listsRouter, 'get', '/');
    const res = createMockResponse();

    await handler(
      {
        user: { id: 'user-1' },
        query: {
          cursor: '2026-04-17T00:00:00.000Z',
          limit: '2',
        },
      },
      res,
    );

    expect(query.lt).toHaveBeenCalledWith('created_at', '2026-04-17T00:00:00.000Z');
    expect(query.limit).toHaveBeenCalledWith(2);
    expect(query.range).not.toHaveBeenCalled();
    expect(res.statusCode).toBe(200);
    expect(res.body).toMatchObject({
      limit: 2,
      cursor: '2026-04-17T00:00:00.000Z',
      nextCursor: '2026-04-14T09:00:00.000Z',
    });
  });

  it('keeps offset pagination fallback in lists endpoint', async () => {
    const rows = [{ id: 'list-9', created_at: '2026-04-01T09:00:00.000Z' }];
    const query = createMockQuery(rows, 8);

    jest.spyOn(supabaseConfig, 'requireSupabase').mockReturnValue({
      from: () => query,
    } as never);

    const handler = getRouteHandler(listsRouter, 'get', '/');
    const res = createMockResponse();

    await handler(
      {
        user: { id: 'user-1' },
        query: {
          offset: '3',
          limit: '2',
        },
      },
      res,
    );

    expect(query.range).toHaveBeenCalledWith(3, 4);
    expect(query.lt).not.toHaveBeenCalled();
    expect(res.statusCode).toBe(200);
    expect(res.body).toMatchObject({
      limit: 2,
      offset: 3,
      count: 8,
    });
  });
});
