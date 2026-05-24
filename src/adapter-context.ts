import { z } from 'zod';

const JsonObjectSchema = z.record(z.unknown());

export interface ExtensionRawEventInput {
  id: string;
  organizationId: string;
  workspaceId?: string | null;
  processId?: string | null;
  idempotencyKey: string;
  sourceEventType: string;
  receivedAt: string | Date;
  payload: unknown;
  metadata?: unknown;
}

export function toAdapterContext(raw: ExtensionRawEventInput) {
  return {
    organizationId: raw.organizationId,
    workspaceId: raw.workspaceId,
    processId: raw.processId,
    rawEventId: raw.id,
    idempotencyKey: raw.idempotencyKey,
    sourceEventType: raw.sourceEventType,
    receivedAt: typeof raw.receivedAt === 'string' ? new Date(raw.receivedAt) : raw.receivedAt,
    payload: JsonObjectSchema.parse(raw.payload),
    metadata: JsonObjectSchema.parse(raw.metadata ?? {}),
  };
}
