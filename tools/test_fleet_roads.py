"""Known-answer checks for directed street path reconstruction."""
import unittest
from export_fleet_roads import shortest_paths


class StreetPathChecks(unittest.TestCase):
    def test_shortest_path_and_parent_chain(self):
        graph = {1: {2: 2, 3: 9}, 2: {3: 3}, 3: {}}
        distances, parents = shortest_paths(graph, 1)
        self.assertEqual(distances[3], 5)
        self.assertEqual(parents, {2: 1, 3: 2})

    def test_one_way_and_isolated_node(self):
        distances, parents = shortest_paths({1: {2: 1}, 2: {}, 3: {}}, 2)
        self.assertEqual(distances, {2: 0})
        self.assertEqual(parents, {})


if __name__ == '__main__':
    unittest.main()
