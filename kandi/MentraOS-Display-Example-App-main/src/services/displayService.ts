import type { GuidanceCard, EscalationResult } from '../types';

const AI_LINE_MAX_CHARS = 100;

function clamp(input: string, maxChars: number): string {
  const safe = input.replace(/\s+/g, ' ').trim();
  if (safe.length <= maxChars) return safe;
  return `${safe.slice(0, maxChars - 1)}…`;
}

function buildAiLine(sayNowAi: string, avoidSayingAi: string): string {
  const combined = `AI: Say ${sayNowAi} | Avoid ${avoidSayingAi}`;
  return clamp(combined, AI_LINE_MAX_CHARS);
}

export class DisplayService {
  readyMessage(): string {
    return [
      'RIGHTSNOW READY',
      'Listening for context...',
      '',
      'Commands: next | repeat | help | sos | stop',
      'Info support only',
    ].join('\n');
  }

  guidanceCard(card: GuidanceCard): string {
    const aiLine = card.aiStatus === 'pending'
      ? 'AI: waiting...'
      : buildAiLine(card.sayNowAi, card.avoidSayingAi);

    return [
      `SCENARIO: ${card.scenario.toUpperCase()}`,
      `SAY(H): ${card.sayNow}`,
      aiLine,
      `AVOID(H): ${card.avoidSaying}`,
      `NEXT: ${card.nextAction}`,
      `CONF: ${card.confidence.toFixed(2)} ${card.sourceType}`,
    ].join('\n');
  }

  escalation(result: EscalationResult): string {
    const lines = ['SOS / HELP', result.message, ''];

    result.resources.forEach((resource, index) => {
      lines.push(`${index + 1}. ${resource.name}: ${resource.phone}`);
    });

    lines.push('Informational support only; not legal advice.');
    return lines.join('\n');
  }

  noHistory(): string {
    return [
      'No prior guidance card yet.',
      'Speak naturally about what is happening.',
      'We will generate a safe next step.',
    ].join('\n');
  }
}
