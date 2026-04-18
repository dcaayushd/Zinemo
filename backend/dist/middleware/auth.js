import { requireSupabase } from '../config/supabase';
export async function authMiddleware(req, res, next) {
    try {
        const authHeader = req.headers.authorization;
        if (!authHeader?.startsWith('Bearer ')) {
            res.status(401).json({ error: 'Missing bearer token' });
            return;
        }
        const token = authHeader.slice('Bearer '.length).trim();
        const client = requireSupabase();
        const { data: { user }, error, } = await client.auth.getUser(token);
        if (error || !user) {
            res.status(401).json({ error: 'Invalid Supabase session token' });
            return;
        }
        req.user = {
            id: user.id,
            email: user.email ?? '',
        };
        next();
    }
    catch (error) {
        next(error);
    }
}
export { authMiddleware as authenticate };
