from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / "site"

required = [
    SITE / "index.html",
    SITE / "styles.css",
    SITE / "app.js",
    ROOT / ".github" / "workflows" / "pages.yml",
]
missing = [str(p.relative_to(ROOT)) for p in required if not p.exists()]
assert not missing, f"missing public-site files: {missing}"

html = (SITE / "index.html").read_text(encoding="utf-8")
css = (SITE / "styles.css").read_text(encoding="utf-8")
js = (SITE / "app.js").read_text(encoding="utf-8")
workflow = (ROOT / ".github" / "workflows" / "pages.yml").read_text(encoding="utf-8")

for phrase in [
    "Offline AI for teachers",
    "AI for teachers.",
    "Paper for students.",
    "Once its AI resources are downloaded, Bayaz runs on-device without an internet connection.",
    "Built for teachers",
    "When a mark is unclear, Bayaz asks the teacher.",
    "Guided lesson planning",
    "Question-level insight",
    "Built around the way the classroom already works.",
]:
    assert phrase in html, f"missing required site copy: {phrase}"

for forbidden in [
    "AI-generated lesson plan",
    "AI generated lesson plan",
    "Watch the real grading flow",
    "Grading is only the beginning",
    "Not mockups",
    "The useful part is knowing when",
    "Built for teachers who still hand out paper",
    "Built for teachers working with paper assessments",
    "Printed assessments stay in the workflow.",
    "Unclear OMR marks go back to the teacher.",
    "not a collection of disconnected AI demos",
    "assets/demo.mp4",
    "<video",
    "↘",
    "↗",
    "↑",
    "—",
    "–",
    "`r`n",
]:
    assert forbidden not in html, f"unwanted site copy/artifact present: {forbidden}"

assert not (SITE / "assets" / "demo.mp4").exists(), "personal demo video must not be published"
assert 'data-parallax' in html, "hero should expose lightweight parallax targets"
assert 'data-lightbox' in html and 'data-lightbox-dialog' in html, "gallery should include a lightbox"
assert 'data-section' in html, "sections should be available for active navigation"
assert "pointermove" in js, "hero interaction should respond to pointer movement"
assert "active" in js, "navigation should track the active section"
assert "dialog" in js.lower(), "gallery script should control the lightbox dialog"
assert ":hover" in css, "site should include interactive hover states"
assert "scroll-snap-type" in css, "mobile workflow should support horizontal snap scrolling"
assert "@media" in css, "site must include responsive styles"
assert "prefers-reduced-motion" in css, "site must respect reduced-motion preference"
assert "path: site" in workflow or "path: 'site'" in workflow, "Pages workflow must deploy site/"

for match in re.findall(r'''(?:src|href)=["']([^"']+)["']''', html):
    if match.startswith(("http://", "https://", "#", "mailto:")):
        continue
    path = (SITE / match.split("?", 1)[0].split("#", 1)[0]).resolve()
    assert path.exists(), f"broken local reference in index.html: {match}"

print("public site smoke test: PASS")


