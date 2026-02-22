import type { Scenario, ScenarioAnalysis } from '../types';

const KEYWORDS: Record<Scenario, string[]> = {
  police: ['police', 'officer', 'detained', 'search', 'arrest', 'badge', 'stop'],
  immigration: ['immigration', 'visa', 'citizenship', 'border', 'ice', 'deport', 'passport'],
  workplace: ['boss', 'manager', 'hr', 'fired', 'terminated', 'write-up', 'shift', 'pay'],
  housing: ['landlord', 'eviction', 'rent', 'lease', 'tenant', 'notice'],
  unknown: [],
};

function scoreScenario(text: string, tokens: string[]): number {
  const normalized = ` ${text.toLowerCase()} `;
  return tokens.reduce((score, token) => {
    const hit = normalized.includes(` ${token} `) || normalized.includes(token);
    return score + (hit ? 1 : 0);
  }, 0);
}

function pickRisk(text: string): 'low' | 'medium' | 'high' {
  const normalized = text.toLowerCase();
  const highTokens = ['threat', 'arrest', 'deport', 'eviction', 'sign now'];
  const mediumTokens = ['pressure', 'questioning', 'demand', 'warning'];

  if (highTokens.some((token) => normalized.includes(token))) return 'high';
  if (mediumTokens.some((token) => normalized.includes(token))) return 'medium';
  return 'low';
}

export class ClassificationService {
  analyze(text: string): ScenarioAnalysis {
    const scenarioScores: Array<{ scenario: Scenario; score: number }> = [
      'police',
      'immigration',
      'workplace',
      'housing',
    ].map((scenario) => ({
      scenario: scenario as Scenario,
      score: scoreScenario(text, KEYWORDS[scenario as Scenario]),
    }));

    scenarioScores.sort((a, b) => b.score - a.score);

    const best = scenarioScores[0];
    const totalMatches = scenarioScores.reduce((sum, item) => sum + item.score, 0);

    if (!best || best.score === 0) {
      return {
        scenario: 'unknown',
        confidence: 0.45,
        riskLevel: pickRisk(text),
        rationale: 'No strong scenario keywords matched.',
      };
    }

    const confidence = Math.min(0.95, 0.55 + best.score * 0.12 + Math.min(totalMatches, 3) * 0.03);

    return {
      scenario: best.scenario,
      confidence,
      riskLevel: pickRisk(text),
      rationale: `Matched ${best.score} primary keyword(s) for ${best.scenario}.`,
    };
  }
}
