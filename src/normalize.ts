import type { GithubRawEventContext, NormalizedOperationalEventOutput } from './types.js';
import {
  actorFromPayload,
  deliveryId,
  derivePullRequestApproved,
  normalizeSourceTime,
  numberField,
  recordField,
  resolveCaseId,
  resolvePullRequestId,
  stringField,
} from './utils.js';

function baseFields(ctx: GithubRawEventContext) {
  return {
    organizationId: ctx.organizationId,
    workspaceId: ctx.workspaceId ?? undefined,
    processId: ctx.processId ?? undefined,
    correlationIds: [ctx.rawEventId, ctx.idempotencyKey],
    sourceSystem: 'github' as const,
  };
}

function normalizePullRequestMerged(ctx: GithubRawEventContext): NormalizedOperationalEventOutput {
  const payload = ctx.payload;
  const pullRequest = recordField(payload, 'pull_request');
  const repository = recordField(payload, 'repository');
  const sender = recordField(payload, 'sender');
  const action = stringField(payload, 'action') ?? stringField(recordField(payload, 'event'), 'action');
  const merged = payload.merged === true || pullRequest.merged === true;
  if (action !== 'closed' || !merged) {
    throw new Error('Unsupported GitHub event for core normalization');
  }

  const caseId = resolveCaseId(payload, pullRequest.body, pullRequest.title, payload.body);
  if (!caseId) throw new Error('Missing required field: caseId');

  const repositoryName = stringField(payload, 'repository') ?? stringField(repository, 'full_name');
  const number = numberField(payload, 'number') ?? numberField(pullRequest, 'number');
  const pullRequestId = resolvePullRequestId(payload, pullRequest, repositoryName);
  if (!pullRequestId) throw new Error('Missing required field: pullRequestId');

  const occurredAt = normalizeSourceTime(
    payload.mergedAt ?? pullRequest.merged_at ?? pullRequest.updated_at,
    ctx.receivedAt,
  );
  const actor = actorFromPayload(payload);
  const githubActor = Object.keys(actor).length > 0 ? actor : { login: stringField(sender, 'login') };
  const approved = derivePullRequestApproved(payload, pullRequest);
  const delivery = deliveryId(ctx.metadata);

  return {
    ...baseFields(ctx),
    caseId,
    eventType: 'repository.pull_request_merged',
    sourceObjectId: pullRequestId,
    actor: githubActor,
    subject: { type: 'pull_request', id: pullRequestId, caseId },
    occurredAt,
    attributes: {
      repository: repositoryName,
      number,
      approved,
      url: stringField(payload, 'url') ?? stringField(pullRequest, 'html_url'),
      deliveryId: delivery,
    },
    dedupeKey: `github:pull_request:${pullRequestId}:merged`,
    evidence: [
      {
        evidenceType: 'pull_request',
        title: stringField(payload, 'title') ?? stringField(pullRequest, 'title') ?? `Pull request ${pullRequestId}`,
        sourceObjectId: pullRequestId,
        capturedAt: occurredAt,
        payload: {
          action,
          repository: repositoryName,
          number,
          title: stringField(payload, 'title') ?? stringField(pullRequest, 'title'),
          url: stringField(payload, 'url') ?? stringField(pullRequest, 'html_url'),
          mergedAt: occurredAt.toISOString(),
          approved,
          actor: githubActor,
          deliveryId: delivery,
        },
        dedupeKey: `github:evidence:pull_request:${pullRequestId}`,
      },
    ],
    intents: [
      {
        type: 'case.link_external_evidence',
        targetType: 'case',
        targetId: caseId,
        reason: 'GitHub pull request merge produced evidence for a linked operational case.',
        attributes: { evidenceType: 'pull_request', sourceObjectId: pullRequestId },
        idempotencyKey: `github:intent:link-pr:${pullRequestId}:${caseId}`,
      },
    ],
  };
}

function normalizePullRequestReview(ctx: GithubRawEventContext): NormalizedOperationalEventOutput {
  const payload = ctx.payload;
  const review = recordField(payload, 'review');
  const pullRequest = recordField(payload, 'pull_request');
  const repository = recordField(payload, 'repository');
  const action = stringField(payload, 'action');
  const state = stringField(review, 'state') ?? stringField(payload, 'state');
  if (action !== 'submitted' || state !== 'APPROVED') {
    throw new Error('Unsupported GitHub event for core normalization');
  }

  const caseId = resolveCaseId(payload, pullRequest.body, pullRequest.title, review.body);
  if (!caseId) throw new Error('Missing required field: caseId');

  const repositoryName = stringField(payload, 'repository') ?? stringField(repository, 'full_name');
  const pullRequestId = resolvePullRequestId(payload, pullRequest, repositoryName);
  if (!pullRequestId) throw new Error('Missing required field: pullRequestId');

  const occurredAt = normalizeSourceTime(review.submitted_at ?? payload.submittedAt, ctx.receivedAt);
  const actor = actorFromPayload(payload);
  const reviewerLogin = stringField(recordField(review, 'user'), 'login');
  const reviewActor = Object.keys(actor).length > 0 ? actor : reviewerLogin ? { login: reviewerLogin } : {};
  const delivery = deliveryId(ctx.metadata);
  const reviewId = stringField(review, 'id') ?? stringField(payload, 'reviewId') ?? `${pullRequestId}:approved`;

  return {
    ...baseFields(ctx),
    caseId,
    eventType: 'approval.recorded',
    sourceObjectId: reviewId,
    actor: reviewActor,
    subject: { type: 'pull_request_review', id: reviewId, pullRequestId, caseId },
    occurredAt,
    attributes: {
      repository: repositoryName,
      pullRequestId,
      state: 'APPROVED',
      approved: true,
      deliveryId: delivery,
    },
    dedupeKey: `github:pull_request_review:${reviewId}:approved`,
    evidence: [
      {
        evidenceType: 'pull_request_review',
        title: `Pull request review approved (${pullRequestId})`,
        sourceObjectId: reviewId,
        capturedAt: occurredAt,
        payload: {
          state: 'APPROVED',
          pullRequestId,
          repository: repositoryName,
          reviewer: reviewActor,
          submittedAt: occurredAt.toISOString(),
          deliveryId: delivery,
        },
        dedupeKey: `github:evidence:pull_request_review:${reviewId}`,
      },
    ],
    intents: [
      {
        type: 'case.link_external_evidence',
        targetType: 'case',
        targetId: caseId,
        reason: 'GitHub pull request review approval produced evidence for a linked operational case.',
        attributes: { evidenceType: 'pull_request_review', sourceObjectId: reviewId },
        idempotencyKey: `github:intent:link-review:${reviewId}:${caseId}`,
      },
    ],
  };
}

function normalizeCheckRun(ctx: GithubRawEventContext): NormalizedOperationalEventOutput {
  const payload = ctx.payload;
  const checkRun = recordField(payload, 'check_run');
  const repository = recordField(payload, 'repository');
  const action = stringField(payload, 'action');
  const status = stringField(checkRun, 'status') ?? stringField(payload, 'status');
  const conclusion = stringField(checkRun, 'conclusion') ?? stringField(payload, 'conclusion');
  const completed = action === 'completed' || status === 'completed';
  if (!completed) {
    throw new Error('Unsupported GitHub event for core normalization');
  }

  const pullRequests = Array.isArray(checkRun.pull_requests) ? checkRun.pull_requests : payload.pullRequests;
  const firstPullRequest =
    Array.isArray(pullRequests) && pullRequests[0] && typeof pullRequests[0] === 'object'
      ? (pullRequests[0] as Record<string, unknown>)
      : recordField(payload, 'pull_request');

  const caseId = resolveCaseId(payload, firstPullRequest.body, firstPullRequest.title, checkRun.name);
  if (!caseId) throw new Error('Missing required field: caseId');

  const repositoryName = stringField(payload, 'repository') ?? stringField(repository, 'full_name');
  const checkRunId =
    stringField(checkRun, 'node_id') ??
    (typeof checkRun.id === 'number' || typeof checkRun.id === 'string' ? String(checkRun.id) : undefined) ??
    stringField(payload, 'checkRunId');
  if (!checkRunId) throw new Error('Missing required field: checkRunId');

  const occurredAt = normalizeSourceTime(checkRun.completed_at ?? payload.completedAt, ctx.receivedAt);
  const actor = actorFromPayload(payload);
  const delivery = deliveryId(ctx.metadata);
  const pullRequestId = resolvePullRequestId(payload, firstPullRequest, repositoryName);
  const checkName = stringField(checkRun, 'name') ?? stringField(payload, 'name') ?? checkRunId;

  return {
    ...baseFields(ctx),
    caseId,
    eventType: 'evidence.observed',
    sourceObjectId: checkRunId,
    actor,
    subject: { type: 'check_run', id: checkRunId, caseId, pullRequestId },
    occurredAt,
    attributes: {
      repository: repositoryName,
      name: checkName,
      conclusion,
      status: status ?? 'completed',
      pullRequestId,
      deliveryId: delivery,
    },
    dedupeKey: `github:check_run:${checkRunId}:completed`,
    evidence: [
      {
        evidenceType: 'check_run',
        title: `CI check ${checkName}`,
        sourceObjectId: checkRunId,
        capturedAt: occurredAt,
        payload: {
          name: checkName,
          conclusion,
          status: status ?? 'completed',
          repository: repositoryName,
          pullRequestId,
          completedAt: occurredAt.toISOString(),
          deliveryId: delivery,
        },
        dedupeKey: `github:evidence:check_run:${checkRunId}`,
      },
    ],
    intents: [
      {
        type: 'case.link_external_evidence',
        targetType: 'case',
        targetId: caseId,
        reason: 'GitHub check run completion produced evidence for a linked operational case.',
        attributes: { evidenceType: 'check_run', sourceObjectId: checkRunId },
        idempotencyKey: `github:intent:link-check:${checkRunId}:${caseId}`,
      },
    ],
  };
}

function normalizeDeployment(ctx: GithubRawEventContext): NormalizedOperationalEventOutput {
  const payload = ctx.payload;
  const deployment = recordField(payload, 'deployment');
  const deploymentStatus = recordField(payload, 'deployment_status');
  const repository = recordField(payload, 'repository');
  const state =
    stringField(deploymentStatus, 'state') ?? stringField(payload, 'state') ?? stringField(deployment, 'status');
  const success = state === 'success';
  if (!success) {
    throw new Error('Unsupported GitHub event for core normalization');
  }

  const caseId = resolveCaseId(
    payload,
    deployment.description,
    deploymentStatus.description,
    stringField(deployment, 'ref'),
  );
  if (!caseId) throw new Error('Missing required field: caseId');

  const repositoryName = stringField(payload, 'repository') ?? stringField(repository, 'full_name');
  const deploymentId =
    stringField(deployment, 'node_id') ??
    (deployment.id != null ? String(deployment.id) : undefined) ??
    stringField(payload, 'deploymentId');
  if (!deploymentId) throw new Error('Missing required field: deploymentId');

  const occurredAt = normalizeSourceTime(
    deploymentStatus.updated_at ?? deployment.updated_at ?? payload.completedAt,
    ctx.receivedAt,
  );
  const actor = actorFromPayload(payload);
  const delivery = deliveryId(ctx.metadata);
  const environment = stringField(deployment, 'environment') ?? stringField(payload, 'environment');

  return {
    ...baseFields(ctx),
    caseId,
    eventType: 'deployment.completed',
    sourceObjectId: deploymentId,
    actor,
    subject: { type: 'deployment', id: deploymentId, caseId, environment },
    occurredAt,
    attributes: {
      repository: repositoryName,
      environment,
      state,
      deliveryId: delivery,
    },
    dedupeKey: `github:deployment:${deploymentId}:completed`,
    evidence: [
      {
        evidenceType: 'deployment',
        title: environment ? `Deployment to ${environment}` : `Deployment ${deploymentId}`,
        sourceObjectId: deploymentId,
        capturedAt: occurredAt,
        payload: {
          environment,
          state,
          repository: repositoryName,
          completedAt: occurredAt.toISOString(),
          deliveryId: delivery,
        },
        dedupeKey: `github:evidence:deployment:${deploymentId}`,
      },
    ],
    intents: [
      {
        type: 'case.link_external_evidence',
        targetType: 'case',
        targetId: caseId,
        reason: 'GitHub deployment completion produced evidence for a linked operational case.',
        attributes: { evidenceType: 'deployment', sourceObjectId: deploymentId },
        idempotencyKey: `github:intent:link-deployment:${deploymentId}:${caseId}`,
      },
    ],
  };
}

function normalizeIssue(ctx: GithubRawEventContext): NormalizedOperationalEventOutput {
  const payload = ctx.payload;
  const issue = recordField(payload, 'issue');
  const repository = recordField(payload, 'repository');
  const action = stringField(payload, 'action');
  if (!action || !['opened', 'reopened', 'edited', 'closed'].includes(action)) {
    throw new Error('Unsupported GitHub event for core normalization');
  }

  const caseId = resolveCaseId(payload, issue.body, issue.title);
  if (!caseId) throw new Error('Missing required field: caseId');

  const repositoryName = stringField(payload, 'repository') ?? stringField(repository, 'full_name');
  const number = numberField(issue, 'number');
  const issueId =
    stringField(issue, 'node_id') ??
    (number != null && repositoryName ? `${repositoryName}#${number}` : undefined) ??
    stringField(payload, 'issueId');
  if (!issueId) throw new Error('Missing required field: issueId');

  const occurredAt = normalizeSourceTime(issue.updated_at ?? issue.created_at ?? payload.updatedAt, ctx.receivedAt);
  const actor = actorFromPayload(payload);
  const delivery = deliveryId(ctx.metadata);
  const title = stringField(issue, 'title') ?? `GitHub issue ${issueId}`;
  const state = stringField(issue, 'state') ?? action;

  return {
    ...baseFields(ctx),
    caseId,
    eventType: 'case.updated',
    sourceObjectId: issueId,
    actor,
    subject: { type: 'github_issue', id: issueId, caseId },
    occurredAt,
    attributes: {
      repository: repositoryName,
      number,
      action,
      state,
      url: stringField(issue, 'html_url'),
      deliveryId: delivery,
    },
    dedupeKey: `github:issue:${issueId}:${action}:${occurredAt.toISOString()}`,
    evidence: [
      {
        evidenceType: 'github_issue',
        title,
        sourceObjectId: issueId,
        capturedAt: occurredAt,
        payload: {
          action,
          state,
          repository: repositoryName,
          number,
          title,
          url: stringField(issue, 'html_url'),
          deliveryId: delivery,
        },
        dedupeKey: `github:evidence:issue:${issueId}:${action}`,
      },
    ],
    intents: [
      {
        type: 'case.link_external_evidence',
        targetType: 'case',
        targetId: caseId,
        reason: 'GitHub issue activity produced evidence for a linked operational case.',
        attributes: { evidenceType: 'github_issue', sourceObjectId: issueId },
        idempotencyKey: `github:intent:link-issue:${issueId}:${caseId}`,
      },
    ],
  };
}

function normalizeIssueComment(ctx: GithubRawEventContext): NormalizedOperationalEventOutput {
  const payload = ctx.payload;
  const comment = recordField(payload, 'comment');
  const issue = recordField(payload, 'issue');
  const repository = recordField(payload, 'repository');
  const action = stringField(payload, 'action');
  if (action !== 'created') {
    throw new Error('Unsupported GitHub event for core normalization');
  }

  const caseId = resolveCaseId(payload, issue.body, issue.title, comment.body);
  if (!caseId) throw new Error('Missing required field: caseId');

  const repositoryName = stringField(payload, 'repository') ?? stringField(repository, 'full_name');
  const issueNumber = numberField(issue, 'number');
  const issueId =
    stringField(issue, 'node_id') ??
    (issueNumber != null && repositoryName ? `${repositoryName}#${issueNumber}` : undefined);
  const commentId =
    stringField(comment, 'id') ??
    (typeof comment.id === 'number' ? String(comment.id) : undefined) ??
    stringField(payload, 'commentId');
  if (!commentId) throw new Error('Missing required field: commentId');

  const occurredAt = normalizeSourceTime(comment.created_at ?? payload.createdAt, ctx.receivedAt);
  const actor = actorFromPayload(payload);
  const delivery = deliveryId(ctx.metadata);
  const sourceObjectId = `${issueId ?? 'issue'}:comment:${commentId}`;

  return {
    ...baseFields(ctx),
    caseId,
    eventType: 'evidence.observed',
    sourceObjectId,
    actor,
    subject: { type: 'issue_comment', id: commentId, issueId, caseId },
    occurredAt,
    attributes: {
      repository: repositoryName,
      issueId,
      issueNumber,
      deliveryId: delivery,
    },
    dedupeKey: `github:issue_comment:${commentId}:created`,
    evidence: [
      {
        evidenceType: 'issue_comment',
        title: `Issue comment on ${issueId ?? issueNumber ?? commentId}`,
        sourceObjectId,
        capturedAt: occurredAt,
        payload: {
          commentId,
          issueId,
          issueNumber,
          repository: repositoryName,
          bodyPreview: typeof comment.body === 'string' ? comment.body.slice(0, 500) : undefined,
          deliveryId: delivery,
        },
        dedupeKey: `github:evidence:issue_comment:${commentId}`,
      },
    ],
    intents: [
      {
        type: 'case.link_external_evidence',
        targetType: 'case',
        targetId: caseId,
        reason: 'GitHub issue comment produced evidence for a linked operational case.',
        attributes: { evidenceType: 'issue_comment', sourceObjectId },
        idempotencyKey: `github:intent:link-comment:${commentId}:${caseId}`,
      },
    ],
  };
}

export function normalizeGithubRawEvent(ctx: GithubRawEventContext): NormalizedOperationalEventOutput {
  switch (ctx.sourceEventType) {
    case 'pull_request':
      return normalizePullRequestMerged(ctx);
    case 'pull_request_review':
      return normalizePullRequestReview(ctx);
    case 'check_run':
      return normalizeCheckRun(ctx);
    case 'deployment':
    case 'deployment_status':
      return normalizeDeployment(ctx);
    case 'issues':
      return normalizeIssue(ctx);
    case 'issue_comment':
      return normalizeIssueComment(ctx);
    default:
      throw new Error(`Unsupported GitHub event for core normalization: ${ctx.sourceEventType}`);
  }
}

export const GITHUB_ADAPTER_SOURCE_EVENT_TYPES = [
  'pull_request',
  'pull_request_review',
  'check_run',
  'deployment',
  'deployment_status',
  'issues',
  'issue_comment',
] as const;

export const GITHUB_ADAPTER_EVIDENCE_TYPES = [
  'pull_request',
  'pull_request_review',
  'check_run',
  'deployment',
  'github_issue',
  'issue_comment',
] as const;
