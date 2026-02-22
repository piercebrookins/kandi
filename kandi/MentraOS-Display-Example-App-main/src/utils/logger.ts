type Level = 'info' | 'warn' | 'error' | 'debug';

const COLORS: Record<Level | 'reset' | 'dim', string> = {
  info: '\x1b[32m',
  warn: '\x1b[33m',
  error: '\x1b[31m',
  debug: '\x1b[36m',
  reset: '\x1b[0m',
  dim: '\x1b[90m',
};

export class Logger {
  constructor(private readonly moduleName: string) {}

  private line(level: Level, message: string, meta?: unknown): string {
    const timestamp = new Date().toISOString();
    const suffix = meta ? ` ${JSON.stringify(meta)}` : '';
    return `${COLORS.dim}${timestamp}${COLORS.reset} ${COLORS[level]}${level.toUpperCase()}${COLORS.reset} ${COLORS.dim}[${this.moduleName}]${COLORS.reset} ${message}${suffix}`;
  }

  info(message: string, meta?: unknown): void {
    console.log(this.line('info', message, meta));
  }

  warn(message: string, meta?: unknown): void {
    console.warn(this.line('warn', message, meta));
  }

  error(message: string, meta?: unknown): void {
    console.error(this.line('error', message, meta));
  }

  debug(message: string, meta?: unknown): void {
    // Always show debug logs for SongRecognition
    if (process.env.LOG_LEVEL === 'debug' || this.moduleName === 'SongRecognition') {
      console.debug(this.line('debug', message, meta));
    }
  }
}

export function createLogger(moduleName: string): Logger {
  return new Logger(moduleName);
}