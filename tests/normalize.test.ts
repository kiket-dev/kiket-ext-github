import { describe, expect, it } from 'vitest';
import { normalizeGithubRawEvent } from '../src/normalize.js';

const CASE_ID = '11111111-1111-4111-8111-111111111111';
const receivedAt = new Date('2026-05-22T10:00:01.000Z');

function baseContext(overrides: Partial<Parameters<typeof normalizeGithubRawEvent>[0]> = {}) {
  return {
    organizationId: 'org-1',
    workspaceId: 'ws-1',
    processId: 'proc-1',
    rawEventId: 'raw-1',
    idempotencyKey: 'idem-1',
    sourceEventType: 'pull_request',
    receivedAt,
    payload: {},
    metadata: { deliveryId: 'delivery-1' },
    ...overrides,
  };
}

describe('normalizeGithubRawEvent', () => {
  it('normalizes merged pull requests', () => {
    const normalized = normalizeGithubRawEvent(
      baseContext({
        payload: {
          action: 'closed',
          merged: true,
          pull_request: {
            merged: true,
            number: 42,
            title: 'Ship billing',
            body: `case: ${CASE_ID}`,
            html_url: 'https://github.com/acme/app/pull/42',
            merged_at: '2026-05-22T11:00:00.000Z',
          },
          repository: { full_name: 'acme/app' },
        },
      }),
    );

    expect(normalized.eventType).toBe('repository.pull_request_merged');
    expect(normalized.caseId).toBe(CASE_ID);
    expect(normalized.evidence[0]?.evidenceType).toBe('pull_request');
  });

  it('normalizes approved pull request reviews', () => {
    const normalized = normalizeGithubRawEvent(
      baseContext({
        sourceEventType: 'pull_request_review',
        payload: {
          action: 'submitted',
          review: {
            state: 'APPROVED',
            id: 'review-1',
            submitted_at: '2026-05-22T12:00:00.000Z',
            user: { login: 'reviewer' },
          },
          pull_request: {
            number: 7,
            title: 'Change',
            body: `caseId: ${CASE_ID}`,
          },
          repository: { full_name: 'acme/app' },
        },
      }),
    );

    expect(normalized.eventType).toBe('approval.recorded');
    expect(normalized.caseId).toBe(CASE_ID);
    expect(normalized.evidence[0]?.evidenceType).toBe('pull_request_review');
  });
});
