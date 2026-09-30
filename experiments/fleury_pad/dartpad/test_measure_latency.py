"""Probe checks with synthetic HTTP responses; not hosted latency evidence."""
import io
import json
import unittest
from unittest.mock import patch
import measure_latency


class Response(io.BytesIO):
    headers = {'x-compile-ms': '125'}


class MeasurementTest(unittest.TestCase):
    def test_first_request_does_not_prewarm_and_checkpoints_are_chained(self):
        responses = [Response(json.dumps(value).encode()) for value in [
            {'buildId': 'test-build'},
            {'result': 'package:fleury_pad/bootstrap.dart', 'deltaDill': 'checkpoint-0'},
            {'result': 'Latency sample 1', 'deltaDill': 'checkpoint-1'},
            {'result': 'Latency sample 2', 'deltaDill': 'checkpoint-2'}]]
        with patch('measure_latency.urlopen', side_effect=responses) as http:
            result = measure_latency.measure('http://127.0.0.1:4346', 'secret-token', rounds=2)
        calls = [call.args[0] for call in http.call_args_list]
        self.assertEqual(calls[0].full_url, 'http://127.0.0.1:4346/api/build')
        self.assertEqual(json.loads(calls[2].data)['deltaDill'], 'checkpoint-0')
        self.assertEqual(json.loads(calls[3].data)['deltaDill'], 'checkpoint-1')
        self.assertFalse(result['coldStartConfirmed'])
        self.assertEqual(result['samples'][1]['serverElapsedMs'], 125)
        for private in ('secret-token', 'checkpoint-0', 'checkpoint-1', 'checkpoint-2'):
            self.assertNotIn(private, json.dumps(result))

    def test_failed_compilation_is_not_reported_as_success(self):
        responses = [Response(json.dumps(value).encode()) for value in [
            {'buildId': 'test-build'}, {'result': 'invalid output'}]]
        with patch('measure_latency.urlopen', side_effect=responses):
            with self.assertRaisesRegex(RuntimeError, 'Initial compilation'):
                measure_latency.measure('http://127.0.0.1:4346')

    def test_rejects_unrelated_hosts_and_unbounded_rounds(self):
        with patch('measure_latency.urlopen') as http:
            for url in ('https://example.com', 'https://bad.run.app.evil.com',
                        'https://user@demo.run.app', 'http://demo.run.app'):
                with self.assertRaises(ValueError):
                    measure_latency.measure(url)
            with self.assertRaises(ValueError):
                measure_latency.measure('http://127.0.0.1:4346', rounds=1000)
            http.assert_not_called()


if __name__ == '__main__':
    unittest.main()
