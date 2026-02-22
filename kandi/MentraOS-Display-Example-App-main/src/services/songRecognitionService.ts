import axios from 'axios';
import { createLogger } from '../utils/logger';

const logger = createLogger('SongRecognition');

interface SongIdentifyResult {
  title: string;
  artist: string;
  provider: 'gemini' | 'shazam' | 'none';
  confidence?: number;
}

interface SongRecognitionOptions {
  geminiApiKey?: string;
  geminiModel: string;
  shazamApiKey?: string;
  shazamApiHost: string;
  auddApiKey?: string;
}

function clamp(input: string): string {
  return input.trim().slice(0, 80);
}

function parseGeminiSong(text: string): { title: string; artist: string } | null {
  const lines = text.split('\n').map((line) => line.trim()).filter(Boolean);
  const titleLine = lines.find((line) => line.toLowerCase().startsWith('title:'));
  const artistLine = lines.find((line) => line.toLowerCase().startsWith('artist:'));

  if (!titleLine || !artistLine) return null;

  const title = clamp(titleLine.replace(/^title:\s*/i, ''));
  const artist = clamp(artistLine.replace(/^artist:\s*/i, ''));
  if (!title || !artist) return null;

  return { title, artist };
}

export class SongRecognitionService {
  constructor(private readonly options: SongRecognitionOptions) {
    logger.info('SongRecognitionService initialized', {
      hasGeminiKey: Boolean(options.geminiApiKey),
      hasShazamKey: Boolean(options.shazamApiKey),
      hasAudDKey: Boolean(options.auddApiKey),
      shazamHost: options.shazamApiHost,
    });
  }

  private async identifyViaGemini(audioBase64: string, mimeType: string): Promise<SongIdentifyResult | null> {
    if (!this.options.geminiApiKey) {
      logger.debug('Gemini skipped - no API key');
      return null;
    }
    logger.debug('Trying Gemini identification', { audioLength: audioBase64.length, mimeType });

    const prompt = [
      'Identify the song from this short live concert audio clip.',
      'Return exactly two lines:',
      'TITLE: <song title>',
      'ARTIST: <artist name>',
      'If uncertain, still provide best guess.',
    ].join('\n');

    const request = axios.post(
      `https://generativelanguage.googleapis.com/v1beta/models/${this.options.geminiModel}:generateContent`,
      {
        contents: [{
          role: 'user',
          parts: [
            { text: prompt },
            {
              inlineData: {
                mimeType,
                data: audioBase64,
              },
            },
          ],
        }],
        generationConfig: {
          temperature: 0.1,
          maxOutputTokens: 120,
        },
      },
      {
        params: { key: this.options.geminiApiKey },
        timeout: 5000,
      },
    );

    const response = await request;
    const text: string = response.data?.candidates?.[0]?.content?.parts?.[0]?.text || '';
    logger.debug('Gemini response', { text: text.substring(0, 200) });

    const parsed = parseGeminiSong(text);
    if (!parsed) {
      logger.debug('Gemini failed to parse song from response');
      return null;
    }

    logger.info('Gemini identified song', { title: parsed.title, artist: parsed.artist });
    return {
      ...parsed,
      provider: 'gemini',
    };
  }

  private async identifyViaAudD(audioBase64: string): Promise<SongIdentifyResult | null> {
    if (!this.options.auddApiKey) {
      logger.debug('AudD skipped - no API key');
      return null;
    }
    logger.info('Trying AudD identification', { audioLength: audioBase64.length });

    try {
      // Convert base64 to buffer for form data
      const audioBuffer = Buffer.from(audioBase64, 'base64');

      const FormData = await import('form-data');
      const form = new FormData.default();
      form.append('api_token', this.options.auddApiKey);
      form.append('file', audioBuffer, { filename: 'audio.wav', contentType: 'audio/wav' });
      form.append('return', 'apple_music,spotify');

      const response = await axios.post(
        'https://api.audd.io/',
        form,
        {
          headers: form.getHeaders(),
          timeout: 15000,
        },
      );

      logger.debug('AudD response', { data: JSON.stringify(response.data).substring(0, 500) });

      if (response.data?.result) {
        const result = response.data.result;
        const title = clamp(result.title || 'Unknown track');
        const artist = clamp(result.artist || 'Unknown artist');

        if (title !== 'Unknown track' && artist !== 'Unknown artist') {
          logger.info('AudD identified song', { title, artist });
          return {
            title,
            artist,
            provider: 'shazam', // Keep as shazam for UI consistency, or change to 'audd'
            confidence: result.score ? result.score / 100 : 0.8,
          };
        }
      }

      logger.debug('AudD returned no match');
      return null;
    } catch (err) {
      logger.warn('AudD identification error', { error: String(err) });
      return null;
    }
  }

  private async identifyViaShazam(audioBase64: string): Promise<SongIdentifyResult | null> {
    if (!this.options.shazamApiKey) {
      logger.warn('Shazam skipped - no API key configured');
      return null;
    }
    logger.info('Trying Shazam identification', { audioLength: audioBase64.length, host: this.options.shazamApiHost });

    const response = await axios.post(
      `https://${this.options.shazamApiHost}/songs/v2/detect`,
      audioBase64,
      {
        headers: {
          'Content-Type': 'text/plain',
          'X-RapidAPI-Key': this.options.shazamApiKey,
          'X-RapidAPI-Host': this.options.shazamApiHost,
        },
        params: {
          timezone: 'America/Chicago',
          locale: 'en-US',
        },
        timeout: 10000,
      },
    );

    logger.debug('Shazam response', { data: JSON.stringify(response.data).substring(0, 500) });

    // Check if we got any matches
    const matches = response.data?.matches || [];
    if (matches.length === 0) {
      logger.debug('Shazam returned no matches');
      return null; // No match found
    }

    // Extract track info from response - Shazam v2 API structure
    const track = response.data?.track || {};
    const title = clamp(track.title || 'Unknown track');
    const artist = clamp(track.subtitle || 'Unknown artist');

    if (title === 'Unknown track' && artist === 'Unknown artist') {
      logger.debug('Shazam returned matches but no track info');
      return null;
    }

    logger.info('Shazam identified song', { title, artist, matches: matches.length });
    return {
      title,
      artist,
      provider: 'shazam',
      confidence: matches.length > 0 ? 0.85 : undefined,
    };
  }

  async identifySong(audioBase64: string, mimeType = 'audio/m4a'): Promise<SongIdentifyResult> {
    logger.debug('Starting song identification', { audioLength: audioBase64.length, mimeType });

    // Try AudD first (most reliable)
    try {
      const audd = await this.identifyViaAudD(audioBase64);
      if (audd) return audd;
    } catch (err) {
      logger.warn('AudD identification failed', { error: String(err) });
    }

    try {
      const gemini = await this.identifyViaGemini(audioBase64, mimeType);
      if (gemini) return gemini;
    } catch (err) {
      logger.warn('Gemini identification failed', { error: String(err) });
    }

    try {
      const shazam = await this.identifyViaShazam(audioBase64);
      if (shazam) return shazam;
    } catch (err) {
      logger.warn('Shazam identification failed', { error: String(err) });
    }

    logger.info('No song identified by any provider');
    return {
      title: 'Unknown track',
      artist: 'Try another sample',
      provider: 'none',
    };
  }
}
