import type { FestivalOverlayState, FriendOverlayItem, HearingOverlayPayload } from '../types/festival';

/**
 * Clamp string to max length, adding ellipsis if truncated.
 * NOTE: SDK may have additional display limits beyond this clamp.
 * If you see 4-character truncation, check MENTRA_VIEW_TYPE env var.
 */
function clamp(input: string, max: number): string {
  if (input.length <= max) return input;
  return `${input.slice(0, max - 1)}…`;
}

/** Max chars per line for display. SDK may impose additional limits. */
const MAX_LINE_CHARS = 48;

function riskEmoji(level: HearingOverlayPayload['riskLevel']): string {
  switch (level) {
    case 'safe':
      return '✅';
    case 'caution':
      return '⚠️';
    case 'risk':
      return '🚨';
    default:
      return '⚪';
  }
}

function formatFriendMeters(distanceMeters?: number): string {
  if (typeof distanceMeters !== 'number' || !Number.isFinite(distanceMeters)) {
    return '--m';
  }
  if (distanceMeters < 1) {
    return `${distanceMeters.toFixed(1)}m`;
  }
  return `${Math.round(distanceMeters)}m`;
}

function friendLine(friend: FriendOverlayItem): string {
  const meters = formatFriendMeters(friend.distanceMeters);
  return clamp(`${friend.name} ${meters}`, MAX_LINE_CHARS);
}

function formatSafeTime(minutes: number): string {
  if (minutes > 60) {
    const hours = Math.round((minutes / 60) * 10) / 10;
    return `${hours}h`;
  }
  return `${minutes}m`;
}

export class FestivalDisplayService {
  readyMessage(): string {
    return [
      'FESTIVAL ASSIST READY',
      'Waiting for iPhone data...',
      'Send: /api/overlay/hearing',
      'Send: /api/overlay/friends',
      'Tip: /api/test/glasses',
    ].join('\n');
  }

  renderOverlay(state: FestivalOverlayState): string {
    const hearing = state.hearing;
    const friends = state.friends?.friends || [];

    const line1 = hearing
      ? clamp(`SOUND ${Math.round(hearing.db)}dB ${riskEmoji(hearing.riskLevel)}`, MAX_LINE_CHARS)
      : 'SOUND --dB ⚪';

    const line2 = hearing
      ? clamp(`SAFE ${formatSafeTime(Math.max(0, hearing.safeTimeLeftMin))} TREND ${hearing.trend.toUpperCase()}`, MAX_LINE_CHARS)
      : 'SAFE -- TREND --';

    const safeToStay = hearing
      && hearing.riskLevel === 'safe'
      && hearing.trend !== 'rising';

    const line3 = hearing
      ? safeToStay
        ? 'ACTION Safe to stay here'
        : clamp(`ACTION ${hearing.suggestion}`, MAX_LINE_CHARS)
      : 'ACTION waiting for hearing data';

    const line4 = friends[0]
      ? clamp(`F1 ${friendLine(friends[0])}`, MAX_LINE_CHARS)
      : 'F1 none';

    const line5 = friends[1]
      ? clamp(`F2 ${friendLine(friends[1])}`, MAX_LINE_CHARS)
      : friends.length > 2
        ? clamp(`+${friends.length - 1} more nearby`, MAX_LINE_CHARS)
        : 'F2 none';

    return [line1, line2, line3, line4, line5].join('\n');
  }
}
