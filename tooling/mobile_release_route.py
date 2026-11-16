"""Choose one release platform from a PR label, independent of changed paths."""
import json
import os
from pathlib import Path
import re


def route(event_name, event, ref, sha):
    branch = event.get('repository', {}).get('default_branch', 'main')
    if branch not in {'main', 'master'}:
        raise ValueError('Mobile releases require the main or master default branch')
    result = dict(platform='', operation='skip', revision='', branch=branch,
                  reason='No release platform selected')
    if event_name == 'pull_request':
        pr = event['pull_request']
        if pr['base']['ref'] != branch:
            return {**result, 'reason': 'PR does not target the default release branch'}
        if event.get('action') == 'closed' and not pr.get('merged'):
            return {**result, 'reason': 'Closed without merging; no release'}
        if pr.get('merged') and event.get('action') != 'closed':
            return {**result, 'reason': 'A post-merge label edit does not release again'}
        platforms = {label['name'].casefold().split(':')[1]
                     for label in pr.get('labels', [])
                     if label['name'].casefold() in {'release:ios', 'release:android'}}
        if len(platforms) > 1:
            raise ValueError('Choose exactly one label: release:ios OR release:android')
        if not platforms:
            return {**result, 'reason': 'Add release:ios or release:android to select one platform'}
        platform = platforms.pop()
        operation = 'upload' if pr.get('merged') else 'validate'
        revision = pr.get('merge_commit_sha') if pr.get('merged') else sha
    elif event_name == 'workflow_dispatch':
        inputs = event.get('inputs', {})
        platform = inputs.get('platform')
        operation = inputs.get('operation', 'validate')
        if platform not in {'ios', 'android'}:
            raise ValueError('Select ios or android')
        allowed = {'validate', 'upload', 'submit_for_review', 'promote_production'}
        if operation not in allowed:
            raise ValueError('Unknown release operation')
        if operation == 'submit_for_review' and platform != 'ios':
            raise ValueError('App Review is an iOS operation')
        if operation == 'promote_production' and platform != 'android':
            raise ValueError('Google production promotion is an Android operation')
        if operation != 'validate' and ref != f'refs/heads/{branch}':
            raise ValueError('Store operations must run from the default release branch')
        revision = sha
    else:
        return {**result, 'reason': 'This event does not release apps'}
    if not re.fullmatch(r'[0-9a-f]{40}', revision or ''):
        raise ValueError('An immutable, valid commit SHA is required')
    return dict(platform=platform, operation=operation, revision=revision,
                branch=branch, reason=f'{operation}: {platform} only at {revision[:12]}')


def main():
    event = json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text())
    result = route(os.environ['GITHUB_EVENT_NAME'], event,
                   os.environ['GITHUB_REF'], os.environ['GITHUB_SHA'])
    print(result['reason'])
    with Path(os.environ['GITHUB_OUTPUT']).open('a') as output:
        for key, value in result.items():
            output.write(f'{key}={value}\n')
    if os.environ.get('GITHUB_STEP_SUMMARY'):
        with Path(os.environ['GITHUB_STEP_SUMMARY']).open('a') as output:
            output.write(result['reason'] + '\n')


if __name__ == '__main__':
    main()
