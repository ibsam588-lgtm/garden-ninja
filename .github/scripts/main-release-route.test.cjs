const { test } = require('node:test');
const assert = require('node:assert/strict');
const selectRelease = require('./main-release-route.cjs');
const sha = 'a'.repeat(40);
const repo = { owner: 'example', repo: 'app' };
const pr = (labels = [], overrides = {}) => ({
  merged_at: '2026-11-17T12:00:00Z', merge_commit_sha: sha,
  base: { ref: 'main', repo: { full_name: 'example/app' } },
  labels: labels.map(name => ({ name })), ...overrides,
});
async function run({ event = 'push', ref = 'refs/heads/main', commit = sha, prs = [], inputs = {}, defaultUpload = true, failApi = false } = {}) {
  const outputs = {};
  let calls = 0;
  const result = await selectRelease({
    context: { eventName: event, ref, sha: commit, repo }, inputs, defaultUpload,
    core: { setOutput: (k, v) => { outputs[k] = v; }, info() {} },
    github: { rest: { repos: { async listPullRequestsAssociatedWithCommit(args) {
      calls++; assert.equal(args.commit_sha, sha);
      if (failApi) throw new Error('GitHub API unavailable');
      return { data: prs };
    } } } },
  });
  assert.deepEqual(outputs, result);
  assert.equal(result.revision, sha);
  assert.equal(result.branch, 'main');
  return { ...result, calls };
}
for (const platform of ['ios', 'android']) {
  test(`merged ${platform} label selects only ${platform}`, async () => {
    const r = await run({ prs: [pr([`release:${platform}`])] });
    assert.equal(r.platform, platform); assert.equal(r.upload, 'true');
  });
  test(`main manual ${platform} upload`, async () => {
    const r = await run({ event: 'workflow_dispatch', inputs: { platform } });
    assert.equal(r.platform, platform); assert.equal(r.upload, 'true'); assert.equal(r.calls, 0);
  });
  test(`main manual ${platform} validate`, async () => {
    const r = await run({ event: 'workflow_dispatch', inputs: { platform, upload: false } });
    assert.equal(r.upload, 'false'); assert.equal(r.operation, 'validate');
  });
}
test('unlabelled merge skips both platforms', async () => assert.equal((await run({ prs: [pr()] })).platform, ''));
test('direct push skips both platforms', async () => assert.equal((await run()).platform, ''));
test('unrelated labels skip both platforms', async () => assert.equal((await run({ prs: [pr(['docs'])] })).upload, 'false'));
test('both labels fail before release', async () => assert.rejects(run({ prs: [pr(['release:ios', 'release:android'])] }), /exactly one/));
test('unmerged PR is ignored', async () => assert.equal((await run({ prs: [pr(['release:ios'], { merged_at: null })] })).platform, ''));
test('old merged commit is ignored', async () => assert.equal((await run({ prs: [pr(['release:ios'], { merge_commit_sha: 'b'.repeat(40) })] })).platform, ''));
test('non-main base is ignored', async () => assert.equal((await run({ prs: [pr(['release:ios'], { base: { ref: 'develop', repo: { full_name: 'example/app' } } })] })).platform, ''));
test('another repository is ignored', async () => assert.equal((await run({ prs: [pr(['release:ios'], { base: { ref: 'main', repo: { full_name: 'other/app' } } })] })).platform, ''));
test('ambiguous merge fails', async () => assert.rejects(run({ prs: [pr(['release:ios']), pr(['release:android'])] }), /More than one/));
test('API failure cannot start a release', async () => assert.rejects(run({ failApi: true }), /unavailable/));
for (const event of ['pull_request', 'pull_request_target', 'release', 'workflow_call']) {
  test(`${event} cannot select a release`, async () => assert.rejects(run({ event }), /Only main pushes/));
}
for (const ref of ['refs/heads/develop', 'refs/heads/master', 'refs/pull/1/merge', 'refs/tags/v1']) {
  test(`${ref} cannot select a release`, async () => assert.rejects(run({ ref }), /only on main/));
}
test('bad SHA cannot select a release', async () => assert.rejects(run({ commit: 'main' }), /SHA/));
test('missing manual platform fails', async () => assert.rejects(run({ event: 'workflow_dispatch' }), /exactly one/));
test('unknown manual platform fails', async () => assert.rejects(run({ event: 'workflow_dispatch', inputs: { platform: 'both' } }), /exactly one/));
test('false default keeps validation-only dispatch', async () => assert.equal((await run({ event: 'workflow_dispatch', inputs: { platform: 'ios' }, defaultUpload: false })).upload, 'false'));
test('string false cannot enable upload', async () => assert.equal((await run({ event: 'workflow_dispatch', inputs: { platform: 'ios', upload: 'false' } })).upload, 'false'));
test('explicit operation overrides upload default', async () => assert.equal((await run({ event: 'workflow_dispatch', inputs: { platform: 'ios', operation: 'validate' } })).upload, 'false'));
test('App Review remains an explicit operation', async () => assert.equal((await run({ event: 'workflow_dispatch', inputs: { platform: 'ios', operation: 'submit_for_review' } })).operation, 'submit_for_review'));
test('unsupported operation fails', async () => assert.rejects(run({ event: 'workflow_dispatch', inputs: { platform: 'ios', operation: 'publish-all' } }), /Unsupported/));
