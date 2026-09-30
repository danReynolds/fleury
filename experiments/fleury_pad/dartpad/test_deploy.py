"""Deployment transaction checks; all cloud/HTTP calls are mocked."""
from argparse import Namespace
import io
import json
import unittest
from unittest.mock import patch
import deploy

class DeployTest(unittest.TestCase):
    def args(self, **overrides):
        return Namespace(**{
            'project': 'fleury-test', 'region': 'us-central1', 'service': 'fleury-pad-staging',
            'image': 'us-central1-docker.pkg.dev/fleury-test/pad/fleury-pad@sha256:' + 'a' * 64,
            'runtime_account': 'runtime@fleury-test.iam.gserviceaccount.com',
            'checkpoint_secret': 'checkpoints:1', 'invoker_account': 'deploy@fleury-test.iam.gserviceaccount.com',
            'promote': True, 'cpu_boost': False, **overrides,
        })

    def service(self):
        return {'metadata': {'name': 'fleury-pad-staging', 'annotations': {
            'run.googleapis.com/scalingMode': 'automatic', 'run.googleapis.com/maxScale': '1',
        }}, 'spec': {'template': {'metadata': {'annotations': {
            'autoscaling.knative.dev/maxScale': '1', 'run.googleapis.com/cpu-throttling': 'false',
            'run.googleapis.com/startup-cpu-boost': 'false',
        }}, 'spec': {'containers': [{'resources': {'limits': {'cpu': '1', 'memory': '2Gi'}}}]}}}, 'status': {
            'url': 'https://fleury-pad-staging-abc-uc.a.run.app',
            'latestReadyRevisionName': 'candidate-revision',
            'traffic': [{'tag': 'candidate', 'revisionName': 'candidate-revision',
                         'url': 'https://candidate---fleury-pad-staging-abc-uc.a.run.app'}],
        }}

    def calls(self, policy=None):
        return [json.dumps([self.service()]), json.dumps(policy or {}),
                json.dumps(self.service()), json.dumps(self.service()), 'synthetic-id-token']

    def test_success_smokes_before_promotion_with_canonical_audience(self):
        responses = [io.BytesIO(json.dumps(value).encode()) for value in [
            {'buildId': 'test-build'}, {'deltaDill': 'signed-checkpoint'}, {'result': 'Reload smoke'}]]
        with patch('deploy.command', side_effect=self.calls()) as command, patch('deploy.subprocess.run') as run, patch('deploy.urlopen', side_effect=responses) as http, patch('builtins.print'):
            deploy.deploy(self.args(docs_origin='https://danreynolds.github.io'))
        deployed = run.call_args_list[0].args[0]
        self.assertTrue(any('FLEURY_PAD_DOCS_ORIGIN=https://danreynolds.github.io' in flag for flag in deployed))
        self.assertIn('--no-traffic', deployed)
        self.assertIn('--no-allow-unauthenticated', deployed)
        self.assertIn('--invoker-iam-check', deployed)
        # Releases must preserve the idle and compute-cost policy, including
        # revision settings that could otherwise keep tagged candidates warm.
        for flag in ('--command=/usr/bin/python3',
                     '--args=/app/experiments/fleury_pad/dartpad/supervise.py',
                     '--cpu=1', '--memory=2Gi', '--no-cpu-throttling',
                     '--no-cpu-boost', '--scaling=auto', '--min=0',
                     '--min-instances=0', '--max=1', '--max-instances=1',
                     '--timeout=60s'):
            self.assertIn(flag, deployed)
        self.assertIn('--to-revisions=candidate-revision=100', run.call_args_list[1].args[0])
        self.assertIn('--remove-tags=candidate', run.call_args_list[1].args[0])
        token = command.call_args_list[-1].args[0]
        self.assertEqual(token[token.index('--audiences') + 1], self.service()['status']['url'])
        self.assertTrue(http.call_args_list[0].args[0].full_url.startswith('https://candidate---'))
        self.assertEqual(json.loads(http.call_args_list[-1].args[0].data)['deltaDill'], 'signed-checkpoint')

    def test_cpu_boost_is_explicit_and_verified(self):
        candidate = self.service()
        candidate['spec']['template']['metadata']['annotations']['run.googleapis.com/startup-cpu-boost'] = 'true'
        calls = self.calls()
        calls[3] = json.dumps(candidate)
        responses = [io.BytesIO(json.dumps(value).encode()) for value in [
            {'buildId': 'test-build'}, {'deltaDill': 'signed-checkpoint'}, {'result': 'Reload smoke'}]]
        with patch('deploy.command', side_effect=calls), patch('deploy.subprocess.run') as run, patch('deploy.urlopen', side_effect=responses), patch('builtins.print'):
            deploy.deploy(self.args(cpu_boost=True))
        flags = run.call_args_list[0].args[0]
        self.assertIn('--cpu-boost', flags)
        self.assertNotIn('--no-cpu-boost', flags)
        self.assertIn('--max=1', flags)
        self.assertIn('--cpu=1', flags)
        self.assertIn('--min=0', flags)
        with self.assertRaisesRegex(RuntimeError, 'Effective Cloud Run'):
            deploy.verify_profile(candidate, cpu_boost=False)
        with self.assertRaisesRegex(RuntimeError, 'Effective Cloud Run'):
            deploy.verify_profile(self.service(), cpu_boost=True)

    def test_recovers_from_first_revision_that_never_became_ready(self):
        calls = self.calls()
        calls[2] = json.dumps({'metadata': {'name': 'fleury-pad-staging'},
                               'status': {'latestCreatedRevisionName': 'failed-revision'}})
        responses = [io.BytesIO(json.dumps(value).encode()) for value in [
            {'buildId': 'test-build'}, {'deltaDill': 'signed-checkpoint'}, {'result': 'Reload smoke'}]]
        with patch('deploy.command', side_effect=calls), patch('deploy.subprocess.run'), patch('deploy.urlopen', side_effect=responses), patch('builtins.print') as printed:
            deploy.deploy(self.args())
        receipt = json.loads(printed.call_args.args[0])
        self.assertTrue(receipt['promoted'])
        self.assertEqual(receipt['previousTraffic'], [])

    def test_developer_token_does_not_request_service_account_audience(self):
        with patch('deploy.command', return_value='synthetic-token') as command:
            self.assertEqual(deploy.identity_token('https://example.run.app'), 'synthetic-token')
        command.assert_called_once_with(['gcloud', 'auth', 'print-identity-token'])

    def test_failed_smoke_keeps_previous_traffic(self):
        with patch('deploy.command', side_effect=self.calls()), patch('deploy.subprocess.run') as run, patch('deploy.urlopen', side_effect=OSError('synthetic smoke failure')):
            with self.assertRaises(OSError):
                deploy.deploy(self.args())
        self.assertEqual(run.call_count, 1)
        self.assertIn('--no-traffic', run.call_args.args[0])

    def test_existing_public_service_is_refused_before_mutation(self):
        with patch('deploy.command', side_effect=self.calls({'bindings': [{'members': ['allUsers']}]})), patch('deploy.subprocess.run') as run:
            with self.assertRaisesRegex(ValueError, 'public service'):
                deploy.deploy(self.args())
        run.assert_not_called()

    def test_public_release_keeps_anonymous_access_without_the_staging_proxy(self):
        responses = [io.BytesIO(json.dumps(value).encode()) for value in [
            {'buildId': 'test-build'}, {'deltaDill': 'signed-checkpoint'}, {'result': 'Reload smoke'}]]
        public = self.calls({'bindings': [{'role': 'roles/run.invoker', 'members': ['allUsers']}]})
        with patch('deploy.command', side_effect=public), patch('deploy.subprocess.run') as run, patch('deploy.urlopen', side_effect=responses), patch('builtins.print'):
            deploy.deploy(self.args(public=True, docs_origin='https://danreynolds.github.io'))
        deployed = run.call_args_list[0].args[0]
        self.assertIn('--allow-unauthenticated', deployed)
        self.assertNotIn('--no-allow-unauthenticated', deployed)
        self.assertIn('--invoker-iam-check', deployed)
        env = next(flag for flag in deployed if flag.startswith('--set-env-vars='))
        self.assertNotIn('FLEURY_PAD_PROXY_ORIGIN', env)
        self.assertIn('FLEURY_PAD_DOCS_ORIGIN=https://danreynolds.github.io', env)
        self.assertIn('--to-revisions=candidate-revision=100', run.call_args_list[1].args[0])

    def test_public_release_requires_the_docs_origin(self):
        with patch('deploy.command') as command:
            with self.assertRaisesRegex(ValueError, 'docs-origin'):
                deploy.deploy(self.args(public=True))
            command.assert_not_called()

    def test_docs_origin_rejects_credentials_paths_and_environment_injection(self):
        for origin in ['http://docs.example.com', 'https://user:pass@docs.example.com', 'https://docs.example.com/path', 'https://docs.example.com,OTHER=value']:
            with patch('deploy.command') as command:
                with self.assertRaises(ValueError):
                    deploy.deploy(self.args(docs_origin=origin))
                command.assert_not_called()

    def test_requires_immutable_image_and_secret(self):
        for args in [self.args(image='image:latest'), self.args(checkpoint_secret='checkpoints:latest')]:
            with patch('deploy.command') as command:
                with self.assertRaises(ValueError):
                    deploy.deploy(args)
                command.assert_not_called()

    def test_effective_cap_drift_is_rejected_before_smoke_or_promotion(self):
        # Observed in the real trial: switching manual scaling back to auto
        # resets the service max to 20 unless it is explicitly supplied again.
        candidate = self.service()
        candidate['metadata']['annotations']['run.googleapis.com/maxScale'] = '20'
        calls = self.calls()
        calls[3] = json.dumps(candidate)
        with patch('deploy.command', side_effect=calls), patch('deploy.subprocess.run') as run, patch('deploy.urlopen') as http:
            with self.assertRaisesRegex(RuntimeError, 'Effective Cloud Run'):
                deploy.deploy(self.args())
        self.assertEqual(run.call_count, 1)
        http.assert_not_called()

    def test_concurrent_candidate_is_not_promoted(self):
        candidate = self.service()
        candidate['status']['latestReadyRevisionName'] = 'other-revision'
        calls = self.calls()
        calls[3] = json.dumps(candidate)
        with patch('deploy.command', side_effect=calls), patch('deploy.subprocess.run') as run:
            with self.assertRaisesRegex(RuntimeError, 'concurrently'):
                deploy.deploy(self.args())
        self.assertEqual(run.call_count, 1)

if __name__ == '__main__':
    unittest.main()
