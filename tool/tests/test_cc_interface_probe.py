"""CC smoke evidence must describe the current category feed, not HTML."""
import importlib.util
from pathlib import Path
from unittest import TestCase, main
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("interface_probe", ROOT / "tool/interface_probe.py")
probe = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(probe)


class CCInterfaceProbeTest(TestCase):
    def test_two_actual_offsets_and_valid_empty_lives(self):
        responses = [{"gametype": 3, "lives": [{"cuteid": "12"}]}, {"gametype": "3", "lives": []}]
        with patch.object(probe, "request_json", side_effect=responses) as request:
            probe.cc_category_rooms_probe()
        self.assertEqual(request.call_count, 2)
        self.assertEqual([c.args[0] for c in request.call_args_list], ["https://cc.163.com/api/category/3/"] * 2)
        self.assertEqual([c.args[1]["start"] for c in request.call_args_list], [0, 2])
        self.assertEqual([c.args[1]["size"] for c in request.call_args_list], [2, 2])

    def test_html_legacy_catalogue_and_mismatched_game_fail(self):
        for response in ("<html>official migration</html>", {"game_list": []}, {"gametype": 4, "lives": []}):
            with self.subTest(response=response), patch.object(probe, "request_json", return_value=response):
                with self.assertRaises(ValueError):
                    probe.cc_category_rooms_probe()

    def test_missing_or_oversized_rows_fail(self):
        for rows in (None, {}, [{"cuteid": "12"}] * 3):
            with self.subTest(rows=rows), patch.object(probe, "request_json", return_value={"gametype": 3, "lives": rows}):
                with self.assertRaises(ValueError):
                    probe.cc_category_rooms_probe()

    def test_invalid_room_identity_fails(self):
        for identity in (None, True, 0, 1.5, 9007199254740992, "../12", "0"):
            response = {"gametype": 3, "lives": [{"cuteid": identity}]}
            with self.subTest(identity=identity), patch.object(probe, "request_json", return_value=response):
                with self.assertRaises(ValueError):
                    probe.cc_category_rooms_probe()

    def test_transport_failure_propagates(self):
        with patch.object(probe, "request_json", side_effect=TimeoutError("fixture")):
            with self.assertRaises(TimeoutError):
                probe.cc_category_rooms_probe()


if __name__ == "__main__":
    main()
