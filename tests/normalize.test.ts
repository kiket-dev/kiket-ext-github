import { describe, expect, it } from 'vitest';
import { normalizeGithubRawEvent } from '../src/normalize.js';

const CASE_ID = '11111111-1111-4111-8111-111111111111';
const receivedAt = new Date('2026-04-25T10:00:01.000Z');

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
  it('normalizes merged pull requests with simplified payloads', () => {
    const normalized = normalizeGithubRawEvent(
      baseContext({
        payload: {
          action: 'closed',
          merged: true,
          approved: false,
          caseId: CASE_ID,
          pullRequestId: 'pr-10',
          repository: 'acme/service',
          title: 'Change payment processor',
          mergedAt: '2026-04-25T11:00:00.000Z',
        },
      }),
    );

    expect(normalized.eventType).toBe('repository.pull_request_merged');
    expect(normalized.caseId).toBe(CASE_ID);
    expect(normalized.attributes.approved).toBe(false);
    expect(normalized.evidence[0]?.evidenceType).toBe('pull_request');
  });

  it('derives approval from embedded review records on merge payloads', () => {
    const normalized = normalizeGithubRawEvent(
      baseContext({
        payload: {
          action: 'closed',
          pull_request: {
            merged: true,
            node_id: 'PR_kwDO123',
            number: 42,
            title: 'Deploy billing flow',
            body: `case: ${CASE_ID}`,
            html_url: 'https://github.com/acme/service/pull/42',
            merged_at: '2026-04-25T10:00:00.000Z',
          },
          repository: { full_name: 'acme/service' },
          reviews: [{ state: 'APPROVED', user: { login: 'reviewer' } }],
        },
      }),
    );

    expect(normalized.attributes.approved).toBe(true);
    expect(normalized.evidence[0]?.payload.approved).toBe(true);
  });

  it('normalizes approved pull request reviews', () => {
    const normalized = normalizeGithubRawEvent(
      baseContext({
        sourceEventType: 'pull_request_review',
        payload: {
          action: 'submitted',
          pull_request: {
            node_id: 'PR_kwDO123',
            number: 42,
            body: `caseId: ${CASE_ID}`,
          },
          review: {
            id: 'review-1',
            state: 'APPROVED',
            submitted_at: '2026-04-25T09:30:00.000Z',
            user: { login: 'reviewer' },
          },
          repository: { full_name: 'acme/service' },
        },
      }),
    );

    expect(normalized.eventType).toBe('approval.recorded');
    expect(normalized.evidence[0]?.evidenceType).toBe('pull_request_review');
    expect(normalized.attributes.approved).toBe(true);
  });

  it('normalizes completed check runs', () => {
    const normalized = normalizeGithubRawEvent(
      baseContext({
        sourceEventType: 'check_run',
        payload: {
          action: 'completed',
          check_run: {
            node_id: 'CR_kwDO123',
            name: 'ci/build',
            status: 'completed',
            conclusion: 'success',
            completed_at: '2026-04-25T09:45:00.000Z',
            pull_requests: [{ node_id: 'PR_kwDO123', body: `case: ${CASE_ID}` }],
          },
          repository: { full_name: 'acme/service' },
        },
      }),
    );

    expect(normalized.eventType).toBe('evidence.observed');
    expect(normalized.evidence[0]?.evidenceType).toBe('check_run');
    expect(normalized.evidence[0]?.payload.conclusion).toBe('success');
  });

  it('normalizes successful deployment status events', () => {
    const normalized = normalizeGithubRawEvent(
      baseContext({
        sourceEventType: 'deployment_status',
        payload: {
          deployment: {
            node_id: 'DEP_kwDO123',
            environment: 'production',
            description: `case: ${CASE_ID}`,
          },
          deployment_status: {
            state: 'success',
            updated_at: '2026-04-25T10:15:00.000Z',
          },
          repository: { full_name: 'acme/service' },
        },
      }),
    );

    expect(normalized.eventType).toBe('deployment.completed');
    expect(normalized.evidence[0]?.evidenceType).toBe('deployment');
    expect(normalized.attributes.environment).toBe('production');
  });

  it('normalizes GitHub issue lifecycle events', () => {
    const normalized = normalizeGithubRawEvent(
      baseContext({
        sourceEventType: 'issues',
        payload: {
          action: 'opened',
          issue: {
            node_id: 'ISS_kwDO123',
            number: 7,
            title: 'Implement scanner hardening',
            body: `case: ${CASE_ID}`,
            html_url: 'https://github.com/acme/platform/issues/7',
            state: 'open',
            created_at: '2026-04-25T08:00:00.000Z',
          },
          repository: { full_name: 'acme/platform' },
        },
      }),
    );

    expect(normalized.eventType).toBe('case.updated');
    expect(normalized.evidence[0]?.evidenceType).toBe('github_issue');
  });

  it('normalizes GitHub issue comments', () => {
    const normalized = normalizeGithubRawEvent(
      baseContext({
        sourceEventType: 'issue_comment',
        payload: {
          action: 'created',
          issue: {
            node_id: 'ISS_kwDO123',
            number: 7,
            body: `caseId: ${CASE_ID}`,
          },
          comment: {
            id: 9001,
            body: 'Risk review complete — ready for approval.',
            created_at: '2026-04-25T08:30:00.000Z',
          },
          repository: { full_name: 'acme/platform' },
        },
      }),
    );

    expect(normalized.eventType).toBe('evidence.observed');
    expect(normalized.evidence[0]?.evidenceType).toBe('issue_comment');
  });

  it('rejects unsupported GitHub events', () => {
    expect(() =>
      normalizeGithubRawEvent(
        baseContext({
          sourceEventType: 'push',
          payload: { ref: 'refs/heads/main' },
        }),
      ),
    ).toThrow(/Unsupported GitHub event/);
  });
});
