import { createLogger } from '../utils/logger';
import type { AppSession } from '@mentra/sdk';

const logger = createLogger('SafetyService');

// Trigger words for safety alerts
const SAFETY_TRIGGERS = ['banana', 'help', 'emergency', 'sos', 'danger'];

export interface SafetyAlert {
  type: 'safety_alert';
  sessionId: string;
  userId: string;
  triggerWord: string;
  timestamp: number;
  message: string;
}

export class SafetyService {
  private sessions = new Map<string, AppSession>();
  private sessionUserIds = new Map<string, string>();

  registerSession(sessionId: string, session: AppSession, userId: string): void {
    this.sessions.set(sessionId, session);
    this.sessionUserIds.set(sessionId, userId);
    logger.info('Session registered for safety monitoring', { sessionId, userId });
  }

  unregisterSession(sessionId: string): void {
    this.sessions.delete(sessionId);
    this.sessionUserIds.delete(sessionId);
    logger.info('Session unregistered from safety monitoring', { sessionId });
  }

  /**
   * Extract first name from email (before @, before numbers)
   */
  private getUserName(userId: string): string {
    if (!userId || userId === 'unknown') return 'Someone';
    const parts = userId.split('@');
    const localPart = parts[0];
    // Extract letters only at start (e.g., piercebrookins05 -> piercebrookins)
    const match = localPart.match(/^([a-zA-Z]+)/);
    const name = match ? match[1] : localPart;
    // Capitalize first letter
    return name.charAt(0).toUpperCase() + name.slice(1).toLowerCase();
  }

  /**
   * Check if text contains safety trigger words
   */
  checkForTriggers(text: string, sessionId: string): SafetyAlert | null {
    const normalizedText = text.toLowerCase().trim();

    for (const trigger of SAFETY_TRIGGERS) {
      if (normalizedText.includes(trigger)) {
        const userId = this.sessionUserIds.get(sessionId) || 'unknown';
        const userName = this.getUserName(userId);
        logger.warn('Safety trigger detected!', { sessionId, userId, userName, trigger, text: text.substring(0, 100) });

        return {
          type: 'safety_alert',
          sessionId,
          userId,
          triggerWord: trigger,
          timestamp: Date.now(),
          message: `🚨 ${userName} needs help!`,
        };
      }
    }

    return null;
  }

  /**
   * Broadcast safety alert to ALL active sessions
   */
  async broadcastSafetyAlert(alert: SafetyAlert): Promise<void> {
    const sessionCount = this.sessions.size;
    logger.info(`Broadcasting safety alert to ${sessionCount} sessions`, { alert });

    const promises: Promise<void>[] = [];

    for (const [targetSessionId, session] of this.sessions.entries()) {
      // Don't send alert back to the originator
      if (targetSessionId === alert.sessionId) {
        continue;
      }

      promises.push(
        this.sendAlertToSession(session, targetSessionId, alert).catch((err) => {
          logger.error('Failed to send safety alert to session', { targetSessionId, error: String(err) });
        }),
      );
    }

    await Promise.all(promises);
    logger.info('Safety alert broadcast complete');
  }

  private async sendAlertToSession(
    session: AppSession,
    targetSessionId: string,
    alert: SafetyAlert,
  ): Promise<void> {
    // Use the Mentra SDK to show an alert on the glasses
    // We'll use a text wall display with the safety message
    try {
      session.layouts.showTextWall(
        [
          '🚨 SAFETY ALERT! 🚨',
          '',
          `${alert.userId} needs help!`,
          '',
          `Triggered: "${alert.triggerWord}"`,
          '',
          'Check on your friend!',
        ].join('\n'),
        {
          view: 'PINNED' as any,
          durationMs: 10000, // Show for 10 seconds
        },
      );
      logger.debug('Safety alert sent to session', { targetSessionId });
    } catch (err) {
      logger.error('Failed to display safety alert', { targetSessionId, error: String(err) });
      throw err;
    }
  }

  getActiveSessionCount(): number {
    return this.sessions.size;
  }
}

// Singleton instance
export const safetyService = new SafetyService();
