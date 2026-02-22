import type { GuidanceCard, SessionMemory } from '../types';

export class SessionManager {
  private readonly sessions = new Map<string, SessionMemory>();

  upsert(sessionId: string, userId: string): SessionMemory {
    const existing = this.sessions.get(sessionId);
    if (existing) {
      existing.lastUpdatedAt = Date.now();
      existing.active = true;
      this.sessions.set(sessionId, existing);
      return existing;
    }

    const created: SessionMemory = {
      sessionId,
      userId,
      createdAt: Date.now(),
      lastUpdatedAt: Date.now(),
      history: [],
      active: true,
    };

    this.sessions.set(sessionId, created);
    return created;
  }

  get(sessionId: string): SessionMemory | null {
    return this.sessions.get(sessionId) || null;
  }

  appendCard(sessionId: string, card: GuidanceCard): void {
    const session = this.sessions.get(sessionId);
    if (!session) return;

    session.history.push(card);
    session.lastUpdatedAt = Date.now();

    if (session.history.length > 20) {
      session.history = session.history.slice(-20);
    }

    this.sessions.set(sessionId, session);
  }

  getLastCard(sessionId: string): GuidanceCard | null {
    const session = this.sessions.get(sessionId);
    if (!session || session.history.length === 0) return null;
    return session.history[session.history.length - 1];
  }

  replaceLastCard(sessionId: string, card: GuidanceCard): void {
    const session = this.sessions.get(sessionId);
    if (!session || session.history.length === 0) return;

    session.history[session.history.length - 1] = card;
    session.lastUpdatedAt = Date.now();
    this.sessions.set(sessionId, session);
  }

  getCardById(sessionId: string, cardId: string): GuidanceCard | null {
    const session = this.sessions.get(sessionId);
    if (!session) return null;
    return session.history.find((card) => card.id === cardId) || null;
  }

  replaceCardById(sessionId: string, cardId: string, nextCard: GuidanceCard): void {
    const session = this.sessions.get(sessionId);
    if (!session) return;

    const index = session.history.findIndex((card) => card.id === cardId);
    if (index === -1) return;

    session.history[index] = nextCard;
    session.lastUpdatedAt = Date.now();
    this.sessions.set(sessionId, session);
  }

  stop(sessionId: string): void {
    const session = this.sessions.get(sessionId);
    if (!session) return;
    session.active = false;
    session.lastUpdatedAt = Date.now();
    this.sessions.set(sessionId, session);

    setTimeout(() => {
      this.sessions.delete(sessionId);
    }, 300000);
  }
}
