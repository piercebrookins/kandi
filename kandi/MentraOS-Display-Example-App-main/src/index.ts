import express from 'express';
import fs from 'fs';
import path from 'path';
import { AppServer, AppSession, ViewType } from '@mentra/sdk';
import { getConfig } from './config';
import { createLogger } from './utils/logger';
import { FestivalDisplayService } from './services/festivalDisplayService';
import { SongRecognitionService } from './services/songRecognitionService';
import { safetyService } from './services/safetyService';
import type {
  FestivalOverlayRequest,
  FestivalOverlayState,
  FriendsOverlayPayload,
  HearingOverlayPayload,
} from './types/festival';

const config = getConfig();
const logger = createLogger('FestivalAssist');

function buildEndpoint(path: string): string {
  if (config.ngrokUrl && config.ngrokUrl.trim()) {
    const base = config.ngrokUrl.replace(/\/+$/, '');
    return `${base}${path}`;
  }
  return `http://localhost:${config.port}${path}`;
}

function toDirectionHint(input: unknown): 'left' | 'right' | 'ahead' | 'behind' | 'unknown' {
  if (typeof input !== 'string') return 'unknown';
  const value = input.toLowerCase().trim();
  if (value === 'left' || value === 'right' || value === 'ahead' || value === 'behind') {
    return value;
  }
  return 'unknown';
}

function bandToMeters(distanceBand: string): number {
  switch (distanceBand) {
    case 'IMMEDIATE':
      return 1;
    case 'NEAR':
      return 4;
    case 'AREA':
      return 10;
    case 'WEAK':
      return 18;
    default:
      return 12;
  }
}

function estimateMeters(friend: Record<string, unknown>, distanceBand: string): number {
  const directMeters = Number(friend.distanceMeters);
  if (Number.isFinite(directMeters) && directMeters > 0) {
    return Math.min(80, Math.max(0.1, directMeters));
  }

  const rssi = Number(friend.rssi);
  if (Number.isFinite(rssi)) {
    if (rssi >= -60) return 2;
    if (rssi >= -70) return 5;
    if (rssi >= -80) return 10;
    return 16;
  }

  return bandToMeters(distanceBand);
}

function normalizeFriend(friend: unknown): {
  name: string;
  distanceBand: 'IMMEDIATE' | 'NEAR' | 'AREA' | 'WEAK';
  hint: 'left' | 'right' | 'ahead' | 'behind' | 'unknown';
  confidence: number;
  distanceMeters: number;
  azimuthDeg?: number;
  rssi?: number;
} | null {
  if (!friend || typeof friend !== 'object') return null;
  const item = friend as Record<string, unknown>;

  const name = String(item.name || '').trim();
  const distanceBandRaw = String(item.distanceBand || '').toUpperCase().trim();

  if (!name || !distanceBandRaw) return null;

  const distanceBand = (['IMMEDIATE', 'NEAR', 'AREA', 'WEAK'].includes(distanceBandRaw)
    ? distanceBandRaw
    : 'AREA') as 'IMMEDIATE' | 'NEAR' | 'AREA' | 'WEAK';

  const hint = toDirectionHint(item.hint);
  const confidenceRaw = Number(item.confidence);
  const confidence = Number.isFinite(confidenceRaw)
    ? Math.max(0, Math.min(1, confidenceRaw))
    : 0;

  const azimuthDegRaw = Number(item.azimuthDeg);
  const azimuthDeg = Number.isFinite(azimuthDegRaw) ? azimuthDegRaw : undefined;

  const rssiRaw = Number(item.rssi);
  const rssi = Number.isFinite(rssiRaw) ? rssiRaw : undefined;

  const distanceMeters = estimateMeters(item, distanceBand);

  return {
    name,
    distanceBand,
    hint,
    confidence,
    distanceMeters,
    azimuthDeg,
    rssi,
  };
}

class FestivalMentraApp extends AppServer {
  private readonly displayService = new FestivalDisplayService();
  private readonly songRecognitionService = new SongRecognitionService({
    geminiApiKey: config.geminiApiKey,
    geminiModel: config.geminiModel,
    shazamApiKey: config.shazamApiKey,
    shazamApiHost: config.shazamApiHost,
    auddApiKey: config.auddApiKey,
  });
  private readonly sessions = new Map<string, AppSession>();
  private readonly sessionStates = new Map<string, FestivalOverlayState>();
  private readonly sessionUserIds = new Map<string, string>();
  private readonly activeSafetyAlerts = new Map<string, Array<{ type: string; sessionId: string; userId: string; triggerWord: string; timestamp: number; message: string }>>();

  private getUserNameFromId(userId: string): string {
    if (!userId || userId === 'unknown') return 'Someone';
    const parts = userId.split('@');
    const localPart = parts[0];
    // Extract letters only at start (e.g., piercebrookins05 -> piercebrookins)
    const match = localPart.match(/^([a-zA-Z]+)/);
    const name = match ? match[1] : localPart;
    // Capitalize first letter
    return name.charAt(0).toUpperCase() + name.slice(1).toLowerCase();
  }

  private async broadcastSafetyAlert(alert: { type: string; sessionId: string; userId: string; triggerWord: string; timestamp: number; message: string }): Promise<number> {
    let broadcastCount = 0;
    const userName = this.getUserNameFromId(alert.userId);

    // Store alert for each active session (for iOS polling)
    for (const targetSessionId of this.sessions.keys()) {
      if (!this.activeSafetyAlerts.has(targetSessionId)) {
        this.activeSafetyAlerts.set(targetSessionId, []);
      }
      this.activeSafetyAlerts.get(targetSessionId)!.push(alert);
    }

    // Show confirmation to originator first
    const originatorSession = this.sessions.get(alert.sessionId);
    if (originatorSession) {
      try {
        const otherCount = this.sessions.size - 1;
        originatorSession.layouts.showTextWall(
          [
            '🚨 ALERT SENT! 🚨',
            '',
            `You triggered: "${alert.triggerWord}"`,
            '',
            otherCount > 0
              ? `Alert sent to ${otherCount} friend${otherCount > 1 ? 's' : ''}!`
              : 'No friends connected yet',
            '',
            'Help is coming!',
          ].join('\n'),
          {
            view: ViewType.PINNED,
            durationMs: 8000,
          },
        );
      } catch (err) {
        logger.error('Failed to show confirmation to originator', { error: String(err) });
      }
    }

    // Send to OTHER friends' glasses
    for (const [targetSessionId, session] of this.sessions.entries()) {
      // Don't send alert back to the originator
      if (targetSessionId === alert.sessionId) {
        continue;
      }

      try {
        session.layouts.showTextWall(
          [
            '🚨 SAFETY ALERT! 🚨',
            '',
            `${userName} needs help!`,
            '',
            `Triggered: "${alert.triggerWord}"`,
            '',
            'Check on your friend!',
          ].join('\n'),
          {
            view: ViewType.PINNED,
            durationMs: 10000,
          },
        );
        broadcastCount++;
      } catch (err) {
        logger.error('Failed to send safety alert to session', { targetSessionId, error: String(err) });
      }
    }

    logger.info('Safety alert broadcast complete', { broadcastCount, totalSessions: this.sessions.size });
    return broadcastCount;
  }

  constructor() {
    super({
      packageName: config.packageName,
      apiKey: config.mentraApiKey,
      port: config.port,
    });

    const expressApp = this.getExpressApp();
    expressApp.disable('etag');
    expressApp.use('/api', (_req, res, next) => {
      res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate');
      res.setHeader('Pragma', 'no-cache');
      res.setHeader('Expires', '0');
      next();
    });
    expressApp.use('/api/song/identify', express.text({ type: 'text/plain', limit: '25mb' }));
    expressApp.use(express.json({ limit: '25mb' }));

    expressApp.get('/', (_req, res) => {
      res.status(200).json({
        name: 'Festival Assistant Mentra App',
        status: 'ok',
        endpoints: {
          hearingOverlay: buildEndpoint('/api/overlay/hearing'),
          friendsOverlay: buildEndpoint('/api/overlay/friends'),
          sessionList: buildEndpoint('/api/session/list'),
          glassesTest: buildEndpoint('/api/test/glasses'),
          songIdentify: buildEndpoint('/api/song/identify'),
        },
      });
    });

    expressApp.get('/health', (_req, res) => {
      res.status(200).json({
        status: 'ok',
        service: 'festival-assist-mentra',
        activeSessions: this.sessions.size,
        ngrokEnabled: Boolean(config.ngrokUrl),
        endpointBase: config.ngrokUrl || `http://localhost:${config.port}`,
        timestamp: new Date().toISOString(),
      });
    });

    // Debug endpoint to save audio for inspection
    expressApp.post('/api/debug/save-audio', (req, res) => {
      const isPlainText = typeof req.body === 'string';
      const audioBase64 = isPlainText ? req.body.trim() : String(req.body?.audioBase64 || '').trim();
      const filename = `debug-audio-${Date.now()}.wav`;
      const filepath = path.resolve(process.cwd(), filename);

      try {
        const audioBuffer = Buffer.from(audioBase64, 'base64');
        fs.writeFileSync(filepath, audioBuffer);
        logger.info('Debug audio saved', { filename, size: audioBuffer.length });
        res.status(200).json({
          ok: true,
          filename,
          size: audioBuffer.length,
          path: filepath,
        });
      } catch (err) {
        res.status(500).json({ error: 'Failed to save audio', detail: String(err) });
      }
    });

    expressApp.get('/api/session/list', (_req, res) => {
      const sessions = Array.from(this.sessions.keys()).map((sessionId) => {
        const state = this.sessionStates.get(sessionId);
        return {
          sessionId,
          hasHearing: Boolean(state?.hearing),
          friendCount: state?.friends?.friends?.length || 0,
          updatedAt: Math.max(state?.hearing?.timestamp || 0, state?.friends?.timestamp || 0) || null,
        };
      });

      res.status(200).json({
        count: sessions.length,
        sessions,
      });
    });

    expressApp.post('/api/test/glasses', (req, res) => {
      const body = (req.body || {}) as { sessionId?: string };
      const targetSessionId = body.sessionId || Array.from(this.sessions.keys())[0];

      if (!targetSessionId) {
        res.status(400).json({ error: 'No active session found. Connect glasses first.' });
        return;
      }

      const hearing: HearingOverlayPayload = {
        type: 'hearing_overlay',
        timestamp: Date.now(),
        db: 104,
        riskLevel: 'risk',
        safeTimeLeftMin: 6,
        trend: 'rising',
        suggestion: 'Safer side: left',
      };

      const friends: FriendsOverlayPayload = {
        type: 'friends_overlay',
        timestamp: Date.now(),
        friends: [
          { name: 'Sarah', distanceBand: 'NEAR', hint: 'left', confidence: 0.72 },
          { name: 'Jason', distanceBand: 'AREA', hint: 'behind', confidence: 0.51 },
        ],
      };

      this.applyOverlay(targetSessionId, hearing);
      this.applyOverlay(targetSessionId, friends);

      const preview = this.displayService.renderOverlay(this.sessionStates.get(targetSessionId) || {});

      res.status(200).json({
        ok: true,
        sessionId: targetSessionId,
        message: 'Test overlay sent to glasses',
        preview,
      });
    });

    expressApp.post('/api/song/identify', async (req, res) => {
      const isPlainText = typeof req.body === 'string';
      const body = (!isPlainText ? (req.body || {}) : {}) as {
        sessionId?: string;
        audioBase64?: string;
        mimeType?: string;
      };

      const headerSessionId = typeof req.header('x-session-id') === 'string'
        ? String(req.header('x-session-id'))
        : undefined;
      const headerMimeType = typeof req.header('x-mime-type') === 'string'
        ? String(req.header('x-mime-type'))
        : undefined;

      const sessionId = (body.sessionId || headerSessionId || '').trim();
      const audioBase64 = isPlainText ? req.body.trim() : String(body.audioBase64 || '').trim();
      const mimeType = (body.mimeType || headerMimeType || 'audio/m4a').trim();

      logger.info('Song identify request received', {
        transport: isPlainText ? 'text/plain' : 'application/json',
        hasSessionId: Boolean(sessionId),
        hasAudio: Boolean(audioBase64),
        mimeType,
        audioChars: audioBase64.length,
      });

      if (!sessionId) {
        res.status(400).json({
          error: 'sessionId is required',
          hint: 'For text/plain uploads, send x-session-id header.',
        });
        return;
      }

      if (!audioBase64) {
        res.status(400).json({ error: 'audioBase64 is required' });
        return;
      }

      // Save audio for debugging
      const debugFilename = `debug-audio-${Date.now()}-${sessionId.replace(/[^a-z0-9]/gi, '_')}.wav`;
      const debugFilepath = path.resolve(process.cwd(), 'debug-audio', debugFilename);
      try {
        fs.mkdirSync(path.dirname(debugFilepath), { recursive: true });
        fs.writeFileSync(debugFilepath, Buffer.from(audioBase64, 'base64'));
        logger.info('Debug audio saved', { filename: debugFilename, path: debugFilepath });
      } catch (saveErr) {
        logger.warn('Failed to save debug audio', { error: String(saveErr) });
      }

      try {
        logger.debug('Calling song recognition service', { sessionId, audioLength: audioBase64.length });
        const result = await this.songRecognitionService.identifySong(
          audioBase64,
          mimeType,
        );
        logger.info('Song identification result', { sessionId, provider: result.provider, title: result.title, artist: result.artist });

        // Only update display if we actually identified a song
        if (result.provider !== 'none') {
          const state = this.sessionStates.get(sessionId) || {};
          const nextState: FestivalOverlayState = {
            ...state,
            song: {
              title: result.title,
              artist: result.artist,
              provider: result.provider,
              confidence: result.confidence,
              updatedAt: Date.now(),
            },
          };

          this.sessionStates.set(sessionId, nextState);
          this.renderToSession(sessionId, nextState, 'song_identify');
        } else {
          logger.debug('No song identified, not updating display');
        }

        res.status(200).json({
          ok: true,
          sessionId,
          song: result.provider !== 'none' ? {
            title: result.title,
            artist: result.artist,
            provider: result.provider,
            confidence: result.confidence,
            updatedAt: Date.now(),
          } : null,
        });
      } catch (error) {
        logger.error('Song identification endpoint error', { sessionId, error: String(error) });
        res.status(500).json({
          error: 'song_identification_failed',
          detail: String(error),
        });
      }
    });



    // NEW: Manual test endpoint - trigger safety alert immediately
    expressApp.post('/api/test/safety-alert', express.json(), (req, res) => {
      const sessionId = String(req.body?.sessionId || '').trim();
      const keyword = String(req.body?.keyword || 'manual').trim();

      if (!sessionId) {
        res.status(400).json({ error: 'sessionId is required' });
        return;
      }

      const userId = this.sessionUserIds.get(sessionId) || 'unknown';
      const userName = this.getUserNameFromId(userId);
      const alert = {
        type: 'safety_alert' as const,
        sessionId,
        userId,
        triggerWord: keyword,
        timestamp: Date.now(),
        message: `🚨 ${userName} needs help!`,
      };

      // Store in active alerts for ALL sessions
      for (const targetSessionId of this.sessions.keys()) {
        if (!this.activeSafetyAlerts.has(targetSessionId)) {
          this.activeSafetyAlerts.set(targetSessionId, []);
        }
        this.activeSafetyAlerts.get(targetSessionId)!.push(alert);
      }

      logger.info('Manual safety alert triggered', { sessionId, keyword, userName });

      res.status(200).json({
        ok: true,
        message: `Test alert triggered for keyword: ${keyword}`,
        hasAlert: true,
      });
    });

    // NEW: Simple boolean check for safety alerts (iOS widget)
    expressApp.get('/api/friends/has-safety-alert', (req, res) => {
      const sessionId = String(req.query.sessionId || '').trim();

      logger.info('Checking safety alerts', { sessionId, totalSessionsWithAlerts: this.activeSafetyAlerts.size });

      if (!sessionId) {
        res.status(400).json({ error: 'sessionId query parameter is required' });
        return;
      }

      const alerts = this.activeSafetyAlerts.get(sessionId) || [];
      logger.info('Raw alerts for session', { sessionId, alertCount: alerts.length });

      // Filter alerts from last 30 seconds
      const now = Date.now();
      const recentAlerts = alerts.filter((a) => now - a.timestamp < 30000);

      logger.info('Recent alerts', { sessionId, recentCount: recentAlerts.length, now });

      // Clean up old alerts
      if (recentAlerts.length !== alerts.length) {
        this.activeSafetyAlerts.set(sessionId, recentAlerts);
      }

      const hasAlert = recentAlerts.length > 0;
      const latestAlert = hasAlert ? recentAlerts[recentAlerts.length - 1] : null;

      res.status(200).json({
        hasAlert,
        alert: latestAlert,
        timestamp: Date.now(),
      });
    });

    // NEW: Get full safety alerts list (iOS poller)
    expressApp.get('/api/friends/safety-alerts', (req, res) => {
      const sessionId = String(req.query.sessionId || '').trim();

      if (!sessionId) {
        res.status(400).json({ error: 'sessionId query parameter is required' });
        return;
      }

      const alerts = this.activeSafetyAlerts.get(sessionId) || [];

      // Filter alerts from last 5 minutes (300 seconds)
      const now = Date.now();
      const recentAlerts = alerts.filter((a) => now - a.timestamp < 300000);

      // Clean up old alerts
      if (recentAlerts.length !== alerts.length) {
        this.activeSafetyAlerts.set(sessionId, recentAlerts);
      }

      res.status(200).json({
        alerts: recentAlerts,
        count: recentAlerts.length,
      });
    });

    // NEW: Friend safety alert broadcast endpoint
    expressApp.post('/api/friends/safety-alert', express.json(), async (req, res) => {
      const body = req.body as {
        sessionId?: string;
        type?: string;
        message?: string;
        severity?: string;
        source?: string;
        keyword?: string;
      };

      const sessionId = String(body.sessionId || '').trim();
      const message = String(body.message || 'I need help').trim();
      const severity = String(body.severity || 'urgent').trim();
      const source = String(body.source || 'manual').trim();
      const keyword = String(body.keyword || '').trim();

      logger.info('Friend safety alert received', { sessionId, message, severity, source, keyword });

      if (!sessionId) {
        res.status(400).json({ error: 'sessionId is required' });
        return;
      }

      const userId = this.sessionUserIds.get(sessionId) || 'unknown';
      const alert = {
        type: 'safety_alert' as const,
        sessionId,
        userId,
        triggerWord: keyword || 'manual',
        timestamp: Date.now(),
        message: `🚨 ${userId}: ${message}`,
      };

      try {
        // Broadcast to all friends
        const broadcastCount = await this.broadcastSafetyAlert(alert);

        res.status(200).json({
          ok: true,
          broadcastCount,
          message: `Alert sent to ${broadcastCount} friends`,
        });
      } catch (error) {
        logger.error('Failed to broadcast safety alert', { error: String(error) });
        res.status(500).json({ error: 'failed_to_broadcast_alert' });
      }
    });

    // NEW: Accept pre-identified song results from ShazamKit
    expressApp.post('/api/song/result', express.json(), async (req, res) => {
      const body = req.body as {
        sessionId?: string;
        title?: string;
        artist?: string;
        provider?: string;
      };

      const sessionId = String(body.sessionId || '').trim();
      const title = String(body.title || '').trim();
      const artist = String(body.artist || '').trim();
      const provider = String(body.provider || 'shazamkit').trim();

      logger.info('Song result received from ShazamKit', { sessionId, title, artist, provider });

      if (!sessionId) {
        res.status(400).json({ error: 'sessionId is required' });
        return;
      }

      if (!title || !artist) {
        res.status(400).json({ error: 'title and artist are required' });
        return;
      }

      try {
        const state = this.sessionStates.get(sessionId) || {};
        const nextState: FestivalOverlayState = {
          ...state,
          song: {
            title,
            artist,
            provider,
            updatedAt: Date.now(),
          },
        };

        this.sessionStates.set(sessionId, nextState);
        this.renderToSession(sessionId, nextState, 'song_shazamkit');

        res.status(200).json({
          ok: true,
          sessionId,
          song: nextState.song,
        });
      } catch (error) {
        logger.error('Song result endpoint error', { sessionId, error: String(error) });
        res.status(500).json({ error: 'failed_to_update_song' });
      }
    });

    expressApp.post('/api/overlay/hearing', (req, res) => {
      const body = req.body as Partial<HearingOverlayPayload> & { sessionId?: string };
      const sessionId = body.sessionId;

      if (!sessionId) {
        res.status(400).json({ error: 'sessionId is required' });
        return;
      }

      if (typeof body.db !== 'number' || typeof body.safeTimeLeftMin !== 'number' || !body.riskLevel) {
        res.status(400).json({ error: 'Invalid hearing payload' });
        return;
      }

      const payload: HearingOverlayPayload = {
        type: 'hearing_overlay',
        timestamp: typeof body.timestamp === 'number' ? body.timestamp : Date.now(),
        db: body.db,
        riskLevel: body.riskLevel,
        safeTimeLeftMin: body.safeTimeLeftMin,
        trend: body.trend || 'steady',
        suggestion: body.suggestion || 'Step to a quieter zone',
      };

      this.applyOverlay(sessionId, payload);
      res.status(200).json({ ok: true });
    });

    expressApp.post('/api/overlay/friends', (req, res) => {
      const body = req.body as Partial<FriendsOverlayPayload> & { sessionId?: string };
      const sessionId = body.sessionId;

      if (!sessionId) {
        res.status(400).json({ error: 'sessionId is required' });
        return;
      }

      if (!Array.isArray(body.friends)) {
        res.status(400).json({ error: 'Invalid friends payload' });
        return;
      }

      const payload: FriendsOverlayPayload = {
        type: 'friends_overlay',
        timestamp: typeof body.timestamp === 'number' ? body.timestamp : Date.now(),
        friends: body.friends
          .map((friend) => normalizeFriend(friend))
          .filter((friend): friend is NonNullable<typeof friend> => Boolean(friend)),
      };

      this.applyOverlay(sessionId, payload);
      res.status(200).json({ ok: true });
    });

    expressApp.use((error: unknown, _req: express.Request, res: express.Response, next: express.NextFunction) => {
      const err = error as { type?: string; status?: number; message?: string };
      const isTooLarge = err?.type === 'entity.too.large' || err?.status === 413;
      if (!isTooLarge) {
        next(error);
        return;
      }

      res.status(413).json({
        error: 'payload_too_large',
        message: 'Request body too large. Use text/plain for /api/song/identify (raw base64 in body + x-session-id header) or reduce audio bite size.',
      });
    });
  }

  protected async onSession(session: AppSession, sessionId: string, userId: string): Promise<void> {
    this.sessions.set(sessionId, session);
    if (!this.sessionStates.has(sessionId)) {
      this.sessionStates.set(sessionId, {});
    }

    // Register session with safety monitoring
    safetyService.registerSession(sessionId, session, userId);

    logger.info('Session connected', { sessionId, userId });

    this.renderToSession(sessionId, this.sessionStates.get(sessionId) || {}, 'session_ready');

    // Listen for transcription to detect safety triggers
    logger.info('Registering transcription listener', { sessionId });
    session.events.onTranscription((data) => {
      const text = data.text || '';
      logger.info('Transcription received', { sessionId, text, textLength: text.length });

      if (!text.trim()) {
        logger.debug('Empty transcription, skipping');
        return;
      }

      const alert = safetyService.checkForTriggers(text, sessionId);
      if (alert) {
        logger.info('Trigger detected, broadcasting alert', { sessionId, trigger: alert.triggerWord });

        // STORE ALERT for this session (so API can find it)
        if (!this.activeSafetyAlerts.has(sessionId)) {
          this.activeSafetyAlerts.set(sessionId, []);
        }
        this.activeSafetyAlerts.get(sessionId)!.push(alert);
        logger.info('Alert stored for session', { sessionId, totalAlerts: this.activeSafetyAlerts.get(sessionId)!.length });

        // Broadcast to all friends
        safetyService.broadcastSafetyAlert(alert).catch((err) => {
          logger.error('Failed to broadcast safety alert', { error: String(err) });
        });
      } else {
        logger.debug('No trigger detected in transcription', { text: text.substring(0, 50) });
      }
    });

    session.events.onGlassesBattery((data) => {
      logger.debug('Battery event', data);
    });
  }

  protected async onStop(sessionId: string, userId: string, reason: string): Promise<void> {
    logger.info('Session stopped', { sessionId, userId, reason });
    this.sessions.delete(sessionId);
    this.sessionStates.delete(sessionId);
    safetyService.unregisterSession(sessionId);
  }

  private applyOverlay(sessionId: string, overlay: FestivalOverlayRequest): void {
    const existing = this.sessionStates.get(sessionId) || {};
    const nextState: FestivalOverlayState = {
      ...existing,
      hearing: overlay.type === 'hearing_overlay' ? overlay : existing.hearing,
      friends: overlay.type === 'friends_overlay' ? overlay : existing.friends,
    };

    this.sessionStates.set(sessionId, nextState);

    const session = this.sessions.get(sessionId);
    if (!session) {
      logger.debug('Overlay received for inactive session', {
        sessionId,
        overlayType: overlay.type,
      });
      return;
    }

    this.renderToSession(sessionId, nextState, overlay.type);

    logger.debug('Overlay rendered', {
      sessionId,
      overlayType: overlay.type,
      hasHearing: Boolean(nextState.hearing),
      friendCount: nextState.friends?.friends?.length || 0,
    });
  }

  private renderToSession(
    sessionId: string,
    state: FestivalOverlayState,
    source: string,
  ): void {
    const session = this.sessions.get(sessionId);
    if (!session) {
      logger.debug('Render skipped - no active session', { sessionId, source });
      return;
    }

    try {
      const text = source === 'session_ready'
        ? this.displayService.readyMessage()
        : this.displayService.renderOverlay(state);

      // DEBUG: Log the exact text being sent to help diagnose truncation issues
      logger.debug('Rendering text to glasses', {
        sessionId,
        source,
        textLength: text.length,
        lineCount: text.split('\n').length,
        firstLine: text.split('\n')[0]?.substring(0, 50),
      });

      // WORKAROUND: Some SDK versions truncate ViewType.MAIN to 4 chars per line.
      // Use MENTRA_VIEW_TYPE env var to switch: 'MAIN' | 'PINNED' | 'DEFAULT'
      // Defaulting to PINNED as it seems to have fewer display restrictions.
      const viewTypeMap: Record<string, ViewType> = {
        'MAIN': ViewType.MAIN,
        'PINNED': ViewType.PINNED,
        'DEFAULT': ViewType.DEFAULT,
      };
      const selectedView = viewTypeMap[config.mentraViewType || 'PINNED'] || ViewType.PINNED;

      session.layouts.showTextWall(text, {
        view: selectedView,
        durationMs: undefined,
      });
    } catch (error) {
      const message = String(error);
      const isSocketClosed = message.includes('WebSocket not connected') || message.includes('current state: CLOSED');

      logger.warn('Render failed', {
        sessionId,
        source,
        error: message,
        isSocketClosed,
      });

      if (isSocketClosed) {
        this.sessions.delete(sessionId);
      }
    }
  }
}

logger.info('Starting Festival Assistant Mentra app', {
  port: config.port,
  packageName: config.packageName,
  ngrokUrl: config.ngrokUrl || null,
  hearingEndpoint: buildEndpoint('/api/overlay/hearing'),
  friendsEndpoint: buildEndpoint('/api/overlay/friends'),
  songEndpoint: buildEndpoint('/api/song/identify'),
});

const app = new FestivalMentraApp();
app.start().catch((error) => {
  logger.error('Failed to start app', { error: String(error) });
  process.exit(1);
});
