import axios from 'axios';
import type { Scenario } from '../types';

interface JimmyGuidanceResult {
  sayNow: string;
  avoidSaying: string;
  inferredScenario?: Scenario;
}

interface JimmyChatResponse {
  text: string;
  stats: Record<string, unknown>;
}

const MAX_GUIDANCE_CHARS = 45;
const SCENARIOS: Scenario[] = ['police', 'immigration', 'workplace', 'housing', 'unknown'];

function cleanLine(input: string, fallback: string): string {
  const normalized = input.replace(/^[-*\s]+/, '').trim();
  if (!normalized) return fallback;
  return normalized.slice(0, MAX_GUIDANCE_CHARS);
}

function parseStatsWrappedResponse(raw: string): JimmyChatResponse {
  const startTag = '<|stats|>';
  const endTag = '<|/stats|>';

  const start = raw.indexOf(startTag);
  if (start === -1) return { text: raw.trim(), stats: {} };

  const end = raw.indexOf(endTag, start + startTag.length);
  if (end === -1) return { text: raw.trim(), stats: {} };

  const text = raw.slice(0, start).trim();
  const statsRaw = raw.slice(start + startTag.length, end).trim();

  try {
    return { text, stats: JSON.parse(statsRaw) as Record<string, unknown> };
  } catch {
    return { text, stats: {} };
  }
}

function extractScenarioFromText(raw: string): Scenario | undefined {
  const normalized = raw.toLowerCase();
  if (normalized.includes('immigration') || normalized.includes('visa') || normalized.includes('deport')) return 'immigration';
  if (normalized.includes('police') || normalized.includes('officer') || normalized.includes('pulled over') || normalized.includes('traffic stop')) return 'police';
  if (normalized.includes('landlord') || normalized.includes('rent') || normalized.includes('eviction') || normalized.includes('tenant')) return 'housing';
  if (normalized.includes('boss') || normalized.includes('manager') || normalized.includes('hr') || normalized.includes('work')) return 'workplace';
  return undefined;
}

export class JimmyService {
  constructor(
    private readonly apiKey: string | undefined,
    private readonly model: string,
  ) {}

  async generateGuidance(scenario: Scenario, transcript: string): Promise<JimmyGuidanceResult> {
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

    const headers: Record<string, string> = {
      accept: '*/*',
      'content-type': 'application/json',
      origin: 'https://chatjimmy.ai',
      referer: 'https://chatjimmy.ai/',
      'user-agent': 'rightsnow-mentra/1.0',
    };

    if (this.apiKey && this.apiKey.trim()) {
      headers.Authorization = `Bearer ${this.apiKey}`;
    }

    const response = await axios.post(
      'https://chatjimmy.ai/api/chat',
      {
        messages: [{ role: 'user', content: prompt }],
        chatOptions: {
          selectedModel: this.model,
          systemPrompt: 'You provide concise legal-safety communication guidance. Output must follow requested format exactly.',
          topK: 8,
        },
        attachment: null,
      },
      {
        headers,
        timeout: 20000,
      },
    );

    const raw = typeof response.data === 'string'
      ? response.data
      : JSON.stringify(response.data);

    const parsed = parseStatsWrappedResponse(raw);
    const lines = parsed.text.split('\n').map((line) => line.trim()).filter(Boolean);

    const scenarioRaw = lines.find((line) => line.toLowerCase().startsWith('scenario:')) || '';
    const sayRaw = lines.find((line) => line.toLowerCase().startsWith('say:')) || '';
    const avoidRaw = lines.find((line) => line.toLowerCase().startsWith('avoid:')) || '';

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
