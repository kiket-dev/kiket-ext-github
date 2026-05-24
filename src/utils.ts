export function jsonObject(value: unknown): Record<string, unknown> {
  return value && typeof value === 'object' && !Array.isArray(value) ? (value as Record<string, unknown>) : {};
}

export function normalizeSourceTime(value: unknown, fallback: Date): Date {
  if (typeof value !== 'string') return fallback;
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? fallback : parsed;
}

export function stringField(payload: Record<string, unknown>, key: string): string | undefined {
  const value = payload[key];
  return typeof value === 'string' && value.length > 0 ? value : undefined;
}

export function recordField(payload: Record<string, unknown>, key: string): Record<string, unknown> {
  const value = payload[key];
  return value && typeof value === 'object' && !Array.isArray(value) ? (value as Record<string, unknown>) : {};
}

export function numberField(payload: Record<string, unknown>, key: string): number | undefined {
  const value = payload[key];
  return typeof value === 'number' && Number.isFinite(value) ? value : undefined;
}

export function extractCaseIdFromText(value: unknown): string | undefined {
  if (typeof value !== 'string') return undefined;
  const match = value.match(
    /(?:kiket-case|caseId|case)\s*[:=]\s*([0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})/i,
  );
  return match?.[1];
}

export function actorFromPayload(payload: Record<string, unknown>): Record<string, unknown> {
  const actor = payload.actor;
  if (actor && typeof actor === 'object' && !Array.isArray(actor)) return actor as Record<string, unknown>;
  const sender = recordField(payload, 'sender');
  if (Object.keys(sender).length > 0) return sender;
  const actorId = stringField(payload, 'actorId');
  return actorId ? { id: actorId } : {};
}

export function resolveCaseId(payload: Record<string, unknown>, ...textSources: unknown[]): string | undefined {
  const direct = stringField(payload, 'caseId');
  if (direct) return direct;
  for (const source of textSources) {
    const extracted = extractCaseIdFromText(source);
    if (extracted) return extracted;
  }
  return undefined;
}

export function resolvePullRequestId(
  payload: Record<string, unknown>,
  pullRequest: Record<string, unknown>,
  repositoryName?: string,
): string | undefined {
  const number = numberField(payload, 'number') ?? numberField(pullRequest, 'number');
  const repo = stringField(payload, 'repository') ?? repositoryName;
  return (
    stringField(payload, 'pullRequestId') ??
    stringField(pullRequest, 'node_id') ??
    (repo && number ? `${repo}#${number}` : undefined)
  );
}

export function derivePullRequestApproved(
  payload: Record<string, unknown>,
  pullRequest: Record<string, unknown>,
): boolean {
  if (payload.approved === true || pullRequest.approved === true) return true;
  const reviews = payload.reviews;
  if (Array.isArray(reviews)) {
    for (const review of reviews) {
      if (review && typeof review === 'object' && (review as Record<string, unknown>).state === 'APPROVED') {
        return true;
      }
    }
  }
  return false;
}

export function deliveryId(metadata: Record<string, unknown> | undefined): string | undefined {
  return stringField(jsonObject(metadata), 'deliveryId');
}
