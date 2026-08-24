import unittest

from src.content_validation import (
    has_material_citation, sanitize_plan_body, scaffolding_reference_issues,
)


class MaterialCitationTest(unittest.TestCase):
    def test_detects_real_textbook_references(self):
        self.assertTrue(has_material_citation("Chapter 4 diagram"))
        self.assertTrue(has_material_citation("Ch. 4, section 4.1"))
        self.assertTrue(has_material_citation("Figure 3.7"))
        self.assertTrue(has_material_citation("Excerpt 2"))

    def test_does_not_flag_ordinary_material_names(self):
        self.assertFalse(has_material_citation("protein-rich foods"))
        self.assertFalse(has_material_citation("glass to catch steam"))
        self.assertFalse(has_material_citation("a pinch of salt"))
        self.assertFalse(has_material_citation("electric switch or key"))

    def test_detects_prompt_internal_and_unavailable_references(self):
        self.assertIn("excerpt", scaffolding_reference_issues("Use Excerpt 3."))
        self.assertIn("figure", scaffolding_reference_issues("Copy Figure 3.7."))
        self.assertIn("table", scaffolding_reference_issues("Read Table 4.1."))
        self.assertIn("cross-reference", scaffolding_reference_issues("Use the same apparatus."))

    def test_allows_self_contained_classroom_instructions(self):
        self.assertEqual(
            scaffolding_reference_issues("Draw and label a simple circuit on the board."),
            [],
        )


class SanitizePlanBodyTest(unittest.TestCase):
    def _clean(self, before: str) -> str:
        after = sanitize_plan_body(before)
        self.assertEqual(scaffolding_reference_issues(after), [], after)
        self.assertEqual(sanitize_plan_body(after), after, "not idempotent")
        return after

    def test_removes_parenthesised_excerpt_marker(self):
        self.assertEqual(
            self._clean("- What is a balanced diet? (Excerpt 7)"),
            "- What is a balanced diet?",
        )

    def test_removes_refer_to_excerpt_phrase(self):
        self.assertEqual(
            self._clean("- What did we cover last time? (Refer to Excerpt 3)"),
            "- What did we cover last time?",
        )
        self.assertEqual(
            self._clean("- Function of the thermometer? (Ref. Excerpt 4)"),
            "- Function of the thermometer?",
        )

    def test_removes_inline_excerpt_reference(self):
        self.assertEqual(
            self._clean("Follow the steps in Excerpt 1 to build the oven."),
            "Follow the steps to build the oven.",
        )

    def test_rewrites_figure_reference_to_board_diagram(self):
        self.assertEqual(
            self._clean("Use Figure 5.6 from the textbook to support your explanation."),
            "Use the board diagram to support your explanation.",
        )
        # "Mention Figure N" becomes "Use the board diagram".
        self.assertEqual(
            self._clean("Mention Figure 9.4 and 9.5 from the textbook."),
            "Use the board diagram.",
        )
        # "the chart shown in Figure N" keeps its sentence and terminal period.
        self.assertEqual(
            self._clean("- Define the food pyramid using the chart shown in Figure 3.7."),
            "- Define the food pyramid using a chart on the board.",
        )

    def test_rewrites_table_reference_to_board_diagram(self):
        self.assertEqual(
            self._clean("Use Table 3.4 to explain the deficiency effects."),
            "Use the board diagram to explain the deficiency effects.",
        )

    def test_drops_orphan_marker_left_after_removal(self):
        # A list line that was nothing but a citation collapses to its marker; drop it.
        self.assertEqual(
            self._clean("1. Recall the water cycle.\n2. (Excerpt 5)"),
            "1. Recall the water cycle.",
        )

    def test_preserves_legitimate_adjacent_sentence(self):
        # "Use arrows ..." is a real instruction and must survive next to a figure ref.
        self.assertEqual(
            self._clean(
                "Use arrows to show how heat affects particle motion. "
                "Mention Figure 5.1 and 5.2 from the textbook for visual reference."
            ),
            "Use arrows to show how heat affects particle motion. "
            "Use the board diagram for visual reference.",
        )

    def test_noop_on_clean_content(self):
        clean = "Draw and label a simple circuit on the board. Use the words: cell, wire."
        self.assertEqual(sanitize_plan_body(clean), clean)

    def test_idempotent(self):
        once = sanitize_plan_body("- What is a balanced diet? (Excerpt 7)")
        self.assertEqual(sanitize_plan_body(once), once)


if __name__ == "__main__":
    unittest.main()
