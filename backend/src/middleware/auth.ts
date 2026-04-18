import { type NextFunction, type Request, type Response } from 'express';
import { requireSupabase } from '../config/supabase';

export interface AuthRequest extends Request {
  user?: {
    id: string;
    email: string;
  };
}

export async function authMiddleware(
  req: AuthRequest,
  res: Response,
  next: NextFunction,
) {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader?.startsWith('Bearer ')) {
      res.status(401).json({ error: 'Missing bearer token' });
      return;
    }

    const token = authHeader.slice('Bearer '.length).trim();
    const client = requireSupabase();
    const {
      data: { user },
      error,
    } = await client.auth.getUser(token);

    if (error || !user) {
      res.status(401).json({ error: 'Invalid Supabase session token' });
      return;
    }

    req.user = {
      id: user.id,
      email: user.email ?? '',
    };
    next();
  } catch (error) {
    next(error);
  }
}

export { authMiddleware as authenticate };
