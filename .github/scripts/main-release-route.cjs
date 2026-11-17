const PLATFORMS = ['ios', 'android'];

async function selectRelease({ github, context, core, inputs = {}, defaultUpload = true }) {
  if (context.ref !== 'refs/heads/main') throw new Error('Mobile releases run only on main.');
  if (!/^[a-f0-9]{40}$/i.test(context.sha || '')) throw new Error('A main commit SHA is required.');

  let platform = '';
  let upload = false;
  let operation = 'validate';
  if (context.eventName === 'workflow_dispatch') {
    platform = inputs.platform;
    if (!PLATFORMS.includes(platform)) throw new Error('Choose exactly one mobile platform.');
    const requestedUpload = inputs.upload === undefined ? defaultUpload : inputs.upload === true || inputs.upload === 'true';
    operation = inputs.operation || (requestedUpload ? 'upload' : 'validate');
    if (!['validate', 'upload', 'submit_for_review', 'promote_production'].includes(operation)) {
      throw new Error('Unsupported mobile release operation.');
    }
    upload = operation === 'upload';
  } else if (context.eventName === 'push') {
    const { data } = await github.rest.repos.listPullRequestsAssociatedWithCommit({
      ...context.repo, commit_sha: context.sha, per_page: 100,
    });
    const merged = data.filter(pr => pr.merged_at && pr.base.ref === 'main' &&
      pr.base.repo?.full_name?.toLowerCase() === `${context.repo.owner}/${context.repo.repo}`.toLowerCase() &&
      pr.merge_commit_sha === context.sha);
    if (merged.length > 1) throw new Error('More than one merged PR matches this main commit.');
    const labels = (merged[0]?.labels || []).map(label => label.name);
    const selected = PLATFORMS.filter(value => labels.includes(`release:${value}`));
    if (selected.length > 1) throw new Error('Use exactly one release label. Neither platform was released.');
    platform = selected[0] || '';
    upload = Boolean(platform);
    operation = upload ? 'upload' : 'validate';
    if (!platform) core.info('No release label on this main commit; mobile builds are skipped.');
  } else {
    throw new Error('Only main pushes and explicit main dispatches may select a release.');
  }

  const outputs = {
    platform, upload: String(upload), release: String(upload), operation,
    revision: context.sha, ref: context.sha, commit_sha: context.sha, branch: 'main',
  };
  for (const [name, value] of Object.entries(outputs)) core.setOutput(name, value);
  return outputs;
}

module.exports = selectRelease;
