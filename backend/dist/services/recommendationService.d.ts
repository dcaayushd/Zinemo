import { type CatalogItem } from './tmdbService';
export interface RecommendationResult extends Partial<CatalogItem> {
    tmdb_id: number;
    media_type: 'movie' | 'tv';
    score: number;
    reason: string;
    algorithm: string;
}
export declare class ScratchRecommendationService {
    getForUser(userId: string, genre?: string, limit?: number): Promise<RecommendationResult[]>;
    getSimilar(tmdbId: number, limit?: number): Promise<RecommendationResult[]>;
    triggerTraining(): Promise<boolean>;
}
export declare class HybridRecommendationService {
    getForUser(userId: string, genre?: string, limit?: number): Promise<RecommendationResult[]>;
    getSimilar(tmdbId: number, limit?: number): Promise<RecommendationResult[]>;
    triggerTraining(): Promise<boolean>;
    private getPreferenceCandidates;
    private getVectorCandidates;
    private buildUserEmbedding;
    private mergeAndRank;
}
export declare function getRecommendationMode(): string;
export declare function getRecommendationsForUser(userId: string, genre?: string, limit?: number): Promise<RecommendationResult[]>;
export declare function getSimilarTitles(tmdbId: number, limit?: number): Promise<RecommendationResult[]>;
export declare function triggerRetraining(): Promise<boolean>;
//# sourceMappingURL=recommendationService.d.ts.map