import fs from 'fs';
import path from 'path';
import type { AppConfig } from '../types';

function loadEnvFile(): void {
  const envPath = path.resolve(process.cwd(), '.env');
  if (!fs.existsSync(envPath)) return;

  const lines = fs.readFileSync(envPath, 'utf-8').split(/\r?\n/);
  for (const rawLine of lines) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#') || !line.includes('=')) continue;

    const [keyRaw, ...valueParts] = line.split('=');
    const key = keyRaw.trim();
    const value = valueParts.join('=').trim().replace(/^['"]|['"]$/g, '');

    if (key && !(key in process.env)) {
      process.env[key] = value;
    }
  }
}

function mustEnv(name: string): string {
  const value = process.env[name];
  if (!value || !value.trim()) {
    throw new Error(`${name} is not set in .env file`);
  }
  return value;
}

function clampThreshold(input: number): number {
  if (Number.isNaN(input)) return 0.65;
  return Math.max(0.5, Math.min(input, 0.95));
}

export function getConfig(): AppConfig {
  loadEnvFile();

  return {
    packageName: mustEnv('PACKAGE_NAME'),
    mentraApiKey: mustEnv('MENTRAOS_API_KEY'),
    port: Number.parseInt(process.env.PORT || '3000', 10),
    defaultLocale: process.env.DEFAULT_LOCALE || 'en-US',
    analysisThreshold: clampThreshold(Number.parseFloat(process.env.ANALYSIS_THRESHOLD || '0.65')),
    geminiApiKey: process.env.GEMINI_API_KEY || process.env.GOOGLE_API_KEY,
    geminiModel: process.env.GEMINI_MODEL || 'gemini-2.5-flash',
    jimmyApiKey: process.env.JIMMY_API_KEY,
    jimmyModel: process.env.JIMMY_MODEL || 'llama3.1-8B',
    ngrokUrl: process.env.NGROK_URL || 'https://unlicentiated-unsqueamishly-mahalia.ngrok-free.app',
    shazamApiKey: process.env.SHAZAM_API_KEY,
    shazamApiHost: process.env.SHAZAM_API_HOST || 'shazam-core.p.rapidapi.com',
    auddApiKey: process.env.AUDD_API_KEY,
    // WORKAROUND: SDK may truncate certain ViewTypes. Options: 'MAIN' | 'PINNED' | 'DEFAULT'
    mentraViewType: (process.env.MENTRA_VIEW_TYPE as 'MAIN' | 'PINNED' | 'DEFAULT') || 'PINNED',
  };
}