"""Evaluate the actual candidate expression against trusted/untrusted events."""
import json
from pathlib import Path
import re
from types import SimpleNamespace as NS
import unittest

WORKFLOW = Path(__file__).resolve().parents[1] / '.github/workflows/sdk-integration.yml'

class CandidateTrustTest(unittest.TestCase):
    def test_candidate_event_matrix(self):
        text = WORKFLOW.read_text()
        block = text.split('\n  candidate:', 1)[1].split('\n    strategy:', 1)[0]
        expression = block.split('if:', 1)[1].strip()
        if expression.startswith('>-'):
            expression = ' '.join(expression[2:].split())
        expression = expression.replace('&&', ' and ').replace('||', ' or ')
        cases = [
            ('pull_request', 'owner/repo', 'owner', 'User', 'OWNER', 'owner', 'owner', True),
            ('pull_request', 'owner/repo', 'human', 'User', 'COLLABORATOR', 'human', 'human', True),
            ('pull_request', 'owner/repo', 'dependabot[bot]', 'Bot', 'CONTRIBUTOR', 'dependabot[bot]', 'owner', False),
            ('pull_request', 'owner/repo', 'dependabot[bot]', 'Bot', 'OWNER', 'owner', 'owner', False),
            ('pull_request', 'fork/repo', 'owner', 'User', 'OWNER', 'owner', 'owner', False),
            ('pull_request', 'owner/repo', 'automation[bot]', 'Bot', 'COLLABORATOR', 'owner', 'owner', False),
            ('pull_request', 'owner/repo', 'human', 'User', 'CONTRIBUTOR', 'human', 'human', False),
            ('pull_request', 'owner/repo', 'owner', 'User', 'OWNER', 'dependabot[bot]', 'owner', False),
            ('workflow_dispatch', '', '', '', '', 'owner', 'owner', True),
            ('push', '', '', '', '', 'owner', 'owner', False),
        ]
        for event, repo, author, kind, association, actor, triggering, expected in cases:
            with self.subTest(event=event, repo=repo, author=author, actor=actor):
                github = NS(event_name=event, repository='owner/repo', actor=actor,
                            triggering_actor=triggering, event=NS(pull_request=NS(
                                head=NS(repo=NS(full_name=repo)), user=NS(login=author, type=kind),
                                author_association=association)))
                actual = eval(expression, {'__builtins__': {}}, {
                    'github': github, 'contains': lambda items, item: item in items,
                    'fromJSON': json.loads})
                self.assertEqual(bool(actual), expected)
        quality = text.split('\n  quality:', 1)[1].split('\n  candidate:', 1)[0]
        self.assertNotRegex(quality, r'(?m)^    if:')
        self.assertNotIn('secrets.', quality)

if __name__ == '__main__':
    unittest.main()
