"""Compile real Fleury code and verify the stateless reload protocol."""
import unittest
from config import ROOT
from server import compile_source


class CompilationTest(unittest.TestCase):
    def test_compile_reload_error_and_recovery(self):
        source = (ROOT / 'lib/main.dart').read_text()
        first = compile_source(source)
        self.assertTrue(first['ok'], first)
        self.assertIn('package:fleury_pad/bootstrap.dart', first['libraries'])
        self.assertIn('package:fleury_pad/main.dart', first['libraries'])
        self.assertLess(first['javascriptBytes'], 100_000)
        self.assertLess(first['checkpointBytes'], 20_000)

        changed = source.replace('Hello, Fleury Pad!', 'Edited Dart')
        second = compile_source(changed, first['checkpoint'])
        self.assertTrue(second['ok'], second)
        self.assertEqual(['package:fleury_pad/main.dart'], second['libraries'])
        self.assertIn('Edited Dart', second['javascript'])

        invalid = changed.replace("Text('Count: $_count')", 'Text(undefinedLabel)')
        failed = compile_source(invalid, second['checkpoint'])
        self.assertFalse(failed['ok'])
        self.assertIn('undefinedLabel', failed['diagnostics'])
        self.assertNotIn('checkpoint', failed)

        recovered = compile_source(changed.replace('_count++', '_count += 2'), second['checkpoint'])
        self.assertTrue(recovered['ok'], recovered)

        # A second visitor requires no persistent app/session on the server.
        independent = compile_source(source)
        self.assertTrue(independent['ok'], independent)
        self.assertIn('package:fleury_pad/bootstrap.dart', independent['libraries'])

    def test_rejects_oversized_or_invalid_requests(self):
        with self.assertRaises(ValueError):
            compile_source('x' * 64_001)
        with self.assertRaises(ValueError):
            compile_source(None)
        with self.assertRaises(ValueError):
            compile_source('void main() {}', 'not-valid-base64!')


if __name__ == '__main__':
    unittest.main()
