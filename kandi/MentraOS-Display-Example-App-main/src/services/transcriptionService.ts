import type { TranscriptChunk } from '../types';

const COMMAND_PREFIXES = ['next', 'repeat', 'help', 'sos', 'stop'];

export class TranscriptionService {
  normalize(text: string): string {
    return text.toLowerCase().trim().replace(/\s+/g, ' ');
  }

  toChunk(text: string, isFinal: boolean, userId: string): TranscriptChunk {
    return {
      text,
      isFinal,
      timestamp: new Date().toISOString(),
      userId,
    };
  }

  isCommand(text: string): boolean {
    const normalized = this.normalize(text);
    return COMMAND_PREFIXES.some((prefix) => normalized.startsWith(prefix));
  }

  parseCommand(text: string): 'next' | 'repeat' | 'help' | 'sos' | 'stop' | null {
    const normalized = this.normalize(text);
    if (normalized.startsWith('next')) return 'next';
    if (normalized.startsWith('repeat')) return 'repeat';
    if (normalized.startsWith('help')) return 'help';
    if (normalized.startsWith('sos')) return 'sos';
    if (normalized.startsWith('stop')) return 'stop';
    return null;
  }
}
