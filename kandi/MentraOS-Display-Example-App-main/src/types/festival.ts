export type HearingRiskLevel = 'safe' | 'caution' | 'risk';
export type HearingTrend = 'rising' | 'falling' | 'steady';

export interface HearingOverlayPayload {
  type: 'hearing_overlay';
  timestamp: number;
  db: number;
  riskLevel: HearingRiskLevel;
  safeTimeLeftMin: number;
  trend: HearingTrend;
  suggestion: string;
}

export type DistanceBand = 'IMMEDIATE' | 'NEAR' | 'AREA' | 'WEAK';
export type DirectionHint = 'left' | 'right' | 'ahead' | 'behind' | 'unknown';

export interface FriendOverlayItem {
  name: string;
  distanceBand: DistanceBand;
  hint: DirectionHint;
  confidence: number;
  distanceMeters?: number;
  azimuthDeg?: number;
  rssi?: number;
}

export interface FriendsOverlayPayload {
  type: 'friends_overlay';
  timestamp: number;
  friends: FriendOverlayItem[];
}

export interface SongOverlayState {
  title: string;
  artist: string;
  provider: 'gemini' | 'shazam' | 'shazamkit' | 'none';
  confidence?: number;
  updatedAt: number;
}

export interface FestivalOverlayState {
  hearing?: HearingOverlayPayload;
  friends?: FriendsOverlayPayload;
  song?: SongOverlayState;
}

export type FestivalOverlayRequest =
  | HearingOverlayPayload
  | FriendsOverlayPayload;
