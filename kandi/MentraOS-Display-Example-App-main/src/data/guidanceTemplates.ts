import type { Scenario, GuidanceCard } from '../types';

type Template = Pick<GuidanceCard, 'sayNow' | 'avoidSaying' | 'nextAction'>;

export const DISCLAIMER = 'Informational support only; not legal advice.';

export const GUIDANCE_TEMPLATES: Record<Scenario, Template> = {
  police: {
    sayNow: 'I want a lawyer before I answer.',
    avoidSaying: 'Do not guess or consent to searches.',
    nextAction: 'Ask if you are free to leave.',
  },
  immigration: {
    sayNow: 'I want an immigration lawyer first.',
    avoidSaying: 'Do not sign papers you do not understand.',
    nextAction: 'Ask for translation and legal counsel.',
  },
  workplace: {
    sayNow: 'Please document this request in writing.',
    avoidSaying: 'Do not admit fault without evidence.',
    nextAction: 'Ask for written notice and review time.',
  },
  housing: {
    sayNow: 'Please give this notice in writing.',
    avoidSaying: 'Do not agree to move out right now.',
    nextAction: 'Document details and call tenant aid.',
  },
  unknown: {
    sayNow: 'I need a moment to speak with counsel.',
    avoidSaying: 'Do not volunteer extra details yet.',
    nextAction: 'Stay calm and ask clarifying questions.',
  },
};
