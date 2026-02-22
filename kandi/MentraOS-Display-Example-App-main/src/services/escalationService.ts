import { LEGAL_RESOURCES } from '../data/legalResources';
import type { EscalationResult, GuidanceCard } from '../types';

export class EscalationService {
  trigger(lastCard: GuidanceCard | null): EscalationResult {
    const scenarioTag = lastCard?.scenario || 'unknown';

    const filtered = LEGAL_RESOURCES.filter((resource) =>
      resource.coverage.includes('US') || resource.coverage.includes(scenarioTag),
    ).slice(0, 3);

    const message = [
      'Escalation ready.',
      'Template alert: I need legal support now.',
      `Context: ${scenarioTag}`,
      'Share location and request attorney contact.',
    ].join(' ');

    return {
      message,
      resources: filtered,
      sent: true,
    };
  }
}
