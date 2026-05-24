export type GithubOperationalEventType =
  | 'case.created'
  | 'case.updated'
  | 'workflow.transitioned'
  | 'approval.recorded'
  | 'document.attached'
  | 'evidence.observed'
  | 'repository.pull_request_merged'
  | 'repository.commit_pushed'
  | 'deployment.completed'
  | 'incident.opened'
  | 'contract.signed'
  | 'identity.user_changed'
  | 'policy.version_changed';

export interface GithubRawEventContext {
  organizationId: string;
  workspaceId?: string | null;
  processId?: string | null;
  rawEventId: string;
  idempotencyKey: string;
  sourceEventType: string;
  receivedAt: Date;
  payload: Record<string, unknown>;
  metadata?: Record<string, unknown>;
}

export interface NormalizedEvidenceOutput {
  evidenceType: string;
  title: string;
  sourceObjectId?: string;
  capturedAt: Date;
  payload: Record<string, unknown>;
  dedupeKey: string;
}

export interface NormalizedIntentOutput {
  type: string;
  targetType?: string;
  targetId?: string;
  reason: string;
  attributes: Record<string, unknown>;
  idempotencyKey: string;
}

export interface NormalizedOperationalEventOutput {
  organizationId: string;
  workspaceId?: string;
  processId?: string;
  caseId?: string;
  eventType: GithubOperationalEventType;
  sourceSystem: 'github';
  sourceObjectId?: string;
  actor: Record<string, unknown>;
  subject: Record<string, unknown>;
  occurredAt: Date;
  correlationIds: string[];
  attributes: Record<string, unknown>;
  dedupeKey: string;
  evidence: NormalizedEvidenceOutput[];
  intents: NormalizedIntentOutput[];
}
