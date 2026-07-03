"""
Patch script v2: replaces section 06 in raveclone_audit_pdf.py
Reads new section content from external file to avoid quote nesting issues.
"""

from pathlib import Path

SRC = Path("/home/z/my-project/scripts/raveclone_audit_pdf.py")
NEW_SECTION_FILE = Path("/home/z/my-project/scripts/section06_v2.py.txt")

NEW_SECTION_06 = NEW_SECTION_FILE.read_text(encoding="utf-8")

text = SRC.read_text(encoding="utf-8")

start_marker = "# \u2500\u2500 REDESIGN SECTION (NEW) \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500"
end_marker = "# \u2500\u2500 ROADMAP \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500"

start_idx = text.find(start_marker)
end_idx = text.find(end_marker)

if start_idx == -1:
    raise SystemExit(f"Start marker not found")
if end_idx == -1:
    raise SystemExit(f"End marker not found")
if end_idx < start_idx:
    raise SystemExit("End marker before start")

new_text = text[:start_idx] + NEW_SECTION_06 + text[end_idx:]
SRC.write_text(new_text, encoding="utf-8")

print(f"\u2713 Patched: {SRC}")
print(f"  Replaced {end_idx - start_idx} chars with {len(NEW_SECTION_06)} chars")
