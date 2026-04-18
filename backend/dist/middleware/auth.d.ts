import { type NextFunction, type Request, type Response } from 'express';
export interface AuthRequest extends Request {
    user?: {
        id: string;
        email: string;
    };
}
export declare function authMiddleware(req: AuthRequest, res: Response, next: NextFunction): Promise<void>;
export { authMiddleware as authenticate };
//# sourceMappingURL=auth.d.ts.map