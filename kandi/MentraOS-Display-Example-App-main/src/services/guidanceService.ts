import { randomUUID } from 'crypto';
import { DISCLAIMER, GUIDANCE_TEMPLATES } from '../data/guidanceTemplates';
import type { GuidanceCard, Scenario, ScenarioAnalysis } from '../types';

export class GuidanceService {
  constructor(private readonly analysisThreshold: number) {}

  generate(analysis: ScenarioAnalysis): GuidanceCard {
    const scenario = analysis.confidence >= this.analysisThreshold ? analysis.scenario : 'unknown';
    const template = GUIDANCE_TEMPLATES[scenario];

    return {
      id: randomUUID(),
      scenario,
      sayNow: template.sayNow,
      avoidSaying: template.avoidSaying,
      sayNowAi: 'waiting...',
      avoidSayingAi: 'waiting...',
      aiStatus: 'pending',
      aiProvider: 'none',
      nextAction: template.nextAction,
      confidence: Number(analysis.confidence.toFixed(2)),
      sourceType: analysis.confidence >= this.analysisThreshold ? 'hybrid' : 'template',
      disclaimer: DISCLAIMER,
    };
  }

  followUp(card: GuidanceCard): GuidanceCard {
    return {
      ...card,
      nextAction: `Follow-up: ${card.nextAction}`,
      confidence: Number(Math.max(0.5, card.confidence - 0.05).toFixed(2)),
      sourceType: 'template',
    };
  }

  applyAiGuidance(
    card: GuidanceCard,
    sayNowAi: string,
    avoidSayingAi: string,
    provider: 'gemini' | 'jimmy',
    inferredScenario?: Scenario,
  ): GuidanceCard {
    const shouldAdoptAiScenario = card.scenario === 'unknown'
      && Boolean(inferredScenario)
      && inferredScenario !== 'unknown';

    const scenario = shouldAdoptAiScenario ? inferredScenario! : card.scenario;
    const template = GUIDANCE_TEMPLATES[scenario];

    return {
      ...card,
      scenario,
      sayNow: template.sayNow,
      avoidSaying: template.avoidSaying,
      nextAction: template.nextAction,
      sayNowAi,
      avoidSayingAi,
      aiStatus: 'ready',
      aiProvider: provider,
      sourceType: 'hybrid',
    };
  }

  markAiUnavailable(card: GuidanceCard): GuidanceCard {
    return {
      ...card,
      sayNowAi: 'AI unavailable; use hardcoded.',
      avoidSayingAi: 'AI unavailable; use hardcoded.',
      aiStatus: 'unavailable',
      aiProvider: 'none',
    };
  }
}
