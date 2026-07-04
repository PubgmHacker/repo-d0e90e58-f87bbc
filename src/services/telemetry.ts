// src/services/telemetry.ts — Pack 5: OpenTelemetry tracing
import { trace, context, SpanStatusCode, SpanKind } from '@opentelemetry/api';
import { registerOTel } from '@opentelemetry/auto-instrumentations-node';

const SERVICE_NAME = 'plink-backend';
const SERVICE_VERSION = '1.5.0';

let isInitialized = false;

export function initTelemetry(endpoint?: string) {
  if (isInitialized) return;
  if (!endpoint) {
    console.log('[Telemetry] No OTEL endpoint — skipping init');
    return;
  }
  
  try {
    registerOTel({
      serviceName: SERVICE_NAME,
      serviceVersion: SERVICE_VERSION,
      otelExporterOtlpEndpoint: endpoint,
    });
    isInitialized = true;
    console.log('✅ OpenTelemetry initialized');
  } catch (e: any) {
    console.warn('[Telemetry] init failed:', e.message);
  }
}

// Helper: create span for manual tracing
export function withSpan<T>(
  name: string,
  fn: (span: any) => T | Promise<T>,
  options?: { kind?: SpanKind; attributes?: Record<string, any> }
): T | Promise<T> {
  const tracer = trace.getTracer(SERVICE_NAME);
  return tracer.startActiveSpan(name, { kind: options?.kind }, async (span) => {
    if (options?.attributes) {
      for (const [k, v] of Object.entries(options.attributes)) {
        span.setAttribute(k, v);
      }
    }
    try {
      const result = await fn(span);
      span.setStatus({ code: SpanStatusCode.OK });
      return result;
    } catch (e: any) {
      span.setStatus({ code: SpanStatusCode.ERROR, message: e.message });
      span.recordException(e);
      throw e;
    } finally {
      span.end();
    }
  });
}

// Helper: add attributes to current span
export function setSpanAttribute(key: string, value: any) {
  const span = trace.getActiveSpan();
  if (span) span.setAttribute(key, value);
}

// Helper: add event to current span
export function addSpanEvent(name: string, attributes?: Record<string, any>) {
  const span = trace.getActiveSpan();
  if (span) span.addEvent(name, attributes);
}
