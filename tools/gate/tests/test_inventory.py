import sys
import tempfile
import unittest
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'ui'))

import inventory  # noqa: E402


class InventoryTest(unittest.TestCase):
    def registry(self, text):
        f = tempfile.NamedTemporaryFile('w', suffix='.toml', delete=False, encoding='utf-8')
        f.write(text)
        f.close()
        self.addCleanup(Path(f.name).unlink)
        return f.name

    def test_new_ids_from_the_old_field(self):
        path = self.registry('[[task]]\nid = "A07.6"\nold = ["U.2f", "T02f.1"]\n\n'
                             '[[task]]\nid = "R02.1"\nold = ["U.2i"]\n\n[[task]]\nid = "Z01.1"\n')
        self.assertEqual(inventory.new_ids(path), {'U.2f': 'A07.6', 'U.2i': 'R02.1'})

    def test_one_old_id_for_two_tasks_is_an_error(self):
        path = self.registry('[[task]]\nid = "A07.6"\nold = ["U.2f"]\n\n[[task]]\nid = "A07.7"\nold = ["U.2f"]\n')
        with self.assertRaises(ValueError):
            inventory.new_ids(path)

    def test_an_old_id_without_a_task_is_an_error(self):
        with self.assertRaises(KeyError):
            inventory.renamed({'U.99': Counter(files=1)}, {'U.2f': 'A07.6'}, Counter)

    def test_renamed_and_ordered_by_new_ids(self):
        ids = {'U.2e': 'A08.1', 'U.2f': 'A07.6', 'U.2i': 'R02.1', 'U.1a': 'A01.2', 'U.10b': 'A12.2'}
        table = inventory.renamed({old: [old] for old in ids}, ids, list)
        self.assertEqual(sorted(table, key=inventory.order), ['A01.2', 'A07.6', 'A08.1', 'A12.2', 'R02.1'])
        self.assertEqual(table['A08.1'], ['U.2e'])

    def test_the_real_rules_all_have_new_ids(self):
        ids = inventory.new_ids()
        rules = {task for _, task in inventory.V3 + inventory.TV if task}
        rules |= set(inventory.ITEM_TASK.values())
        self.assertEqual(sorted(rules - ids.keys()), [])


if __name__ == '__main__':
    unittest.main()
