import axios from 'axios';
import type { Scenario } from '../types';

interface GeminiGuidanceResult {
  sayNow: string;
  avoidSaying: string;
  inferredScenario?: Scenario;
}

const MAX_GUIDANCE_CHARS = 45;
const SCENARIOS: Scenario[] = ['police', 'immigration', 'workplace', 'housing', 'unknown'];

function cleanLine(input: string, fallback: string): string {
  const normalized = input.replace(/^[-*\s]+/, '').trim();
  if (!normalized) return fallback;
  return normalized.slice(0, MAX_GUIDANCE_CHARS);
}

function extractScenarioFromText(raw: string): Scenario | undefined {
  const normalized = raw.toLowerCase();
  if (normalized.includes('immigration') || normalized.includes('visa') || normalized.includes('deport')) return 'immigration';
  if (normalized.includes('police') || normalized.includes('officer') || normalized.includes('pulled over') || normalized.includes('traffic stop')) return 'police';
  if (normalized.includes('landlord') || normalized.includes('rent') || normalized.includes('eviction') || normalized.includes('tenant')) return 'housing';
  if (normalized.includes('boss') || normalized.includes('manager') || normalized.includes('hr') || normalized.includes('work')) return 'workplace';
  return undefined;
}

export class GeminiService {
  constructor(
    private readonly apiKey: string,
    private readonly model: string,
  ) {}

  async generateGuidance(scenario: Scenario, transcript: string): Promise<GeminiGuidanceResult> {
    const prompt = [
      'You are assisting with legal-risk communication safety.',
      'Return exactly three lines in plain text:',
      'SCENARIO: <police|immigration|workplace|housing|unknown>',
      'SAY: <one short line, max 45 chars>',
      'AVOID: <one short line, max 45 chars>',
      '',
      `Scenario: ${scenario}`,
      `Transcript context: ${transcript}`,
      '',
      'Rules:',
      '- Keep each line <= 45 characters.',
      '- Be cautious, de-escalatory, and non-confrontational.',
      '- Do not claim legal certainty.',
      '- No extra commentary.',
    ].join('\n');

    const response = await axios.post(
      `https://generativelanguage.googleapis.com/v1beta/models/${this.model}:generateContent`,
      {
        contents: [{ role: 'user', parts: [{ text: prompt }] }],
        generationConfig: {
          temperature: 0.2,
          maxOutputTokens: 120,
        },
      },
      {
        params: { key: this.apiKey },
        timeout: 12000,
      },
    );

    const text: string = response.data?.candidates?.[0]?.content?.parts?.[0]?.text || '';
    const lines = text.split('\n').map((line: string) => line.trim()).filter(Boolean);

    const scenarioRaw = lines.find((line: string) => line.toLowerCase().startsWith('scenario:')) || '';
    const sayRaw = lines.find((line: string) => line.toLowerCase().startsWith('say:')) || '';
    const avoidRaw = lines.find((line: string) => line.toLowerCase().startsWith('avoid:')) || '';

    const inferredRaw = scenarioRaw.replace(/^scenario:\s*/i, '').trim().toLowerCase();
    let inferredScenario = SCENARIOS.includes(inferredRaw as Scenario)
      ? (inferredRaw as Scenario)
      : undefined;

    if (!inferredScenario || inferredScenario === 'unknown') {
      inferredScenario = extractScenarioFromText(transcript);
    }

    const sayNow = cleanLine(sayRaw.replace(/^say:\s*/i, ''), 'I want a lawyer before I answer.');
    const avoidSaying = cleanLine(avoidRaw.replace(/^avoid:\s*/i, ''), 'Do not share extra details right now.');

    return { sayNow, avoidSaying, inferredScenario };
  }
}
