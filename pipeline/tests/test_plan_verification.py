import unittest

from src.content_validation import has_material_citation, scaffolding_reference_issues


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


if __name__ == "__main__":
    unittest.main()
