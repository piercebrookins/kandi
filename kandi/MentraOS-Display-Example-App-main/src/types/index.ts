export type Scenario = 'police' | 'immigration' | 'workplace' | 'housing' | 'unknown';

export type RiskLevel = 'low' | 'medium' | 'high';

export type SourceType = 'template' | 'hybrid';

export type AiProvider = 'gemini' | 'jimmy' | 'none';

export type AiGuidanceStatus = 'pending' | 'ready' | 'unavailable';

export interface TranscriptChunk {
  text: string;
  isFinal: boolean;
  timestamp: string;
  userId: string;
}

export interface ScenarioAnalysis {
  scenario: Scenario;
  confidence: number;
  riskLevel: RiskLevel;
  rationale: string;
}

export interface GuidanceCard {
  id: string;
  scenario: Scenario;
  sayNow: string;
  avoidSaying: string;
  sayNowAi: string;
  avoidSayingAi: string;
  aiStatus: AiGuidanceStatus;
  aiProvider: AiProvider;
  nextAction: string;
  confidence: number;
  sourceType: SourceType;
  disclaimer: string;
}

export interface LegalResource {
  name: string;
  phone: string;
  coverage: string[];
}

export interface EscalationResult {
  message: string;
  resources: LegalResource[];
  sent: boolean;
}

export interface SessionMemory {
  sessionId: string;
  userId: string;
  createdAt: number;
  lastUpdatedAt: number;
  history: GuidanceCard[];
  active: boolean;
}

export interface AppConfig {
  packageName: string;
  mentraApiKey: string;
  port: number;
  defaultLocale: string;
  analysisThreshold: number;
  geminiApiKey?: string;
  geminiModel: string;
  jimmyApiKey?: string;
  jimmyModel: string;
  ngrokUrl?: string;
  shazamApiKey?: string;
  shazamApiHost: string;
  auddApiKey?: string;
  /** ViewType for SDK display - some versions truncate MAIN view to 4 chars */
  mentraViewType?: 'MAIN' | 'PINNED' | 'DEFAULT';
}