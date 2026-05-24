import { describe, expect, it } from 'vitest';
import { GITHUB_ADAPTER_SOURCE_EVENT_TYPES, normalizeGithubRawEvent } from '../src/index.js';

describe('github extension entry', () => {
  it('re-exports github-adapter normalizers', () => {
    expect(GITHUB_ADAPTER_SOURCE_EVENT_TYPES).toContain('pull_request');
    expect(typeof normalizeGithubRawEvent).toBe('function');
  });
});
