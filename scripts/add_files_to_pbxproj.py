#!/usr/bin/env python3
"""
Add new Swift files to Plink.xcodeproj/project.pbxproj.

Xcode requires each source file to be referenced in 3 sections of pbxproj:
  1. PBXBuildFile     — links file to build phase
  2. PBXFileReference — declares file metadata (path, sourceTree, fileType)
  3. PBXGroup         — adds reference to the parent group (folder)
  4. PBXSourcesBuildPhase — adds file to compilation

This script handles all 4 for each file. Idempotent — safe to run multiple
times (checks if file already exists in pbxproj before adding).
"""

import re
import uuid
import sys
from pathlib import Path

PBXPROJ = Path("/home/z/my-project/plink-v2-work/Plink.xcodeproj/project.pbxproj")

# (relative_path, parent_group_hint) — parent_group_hint is a substring
# used to find the right PBXGroup entry (e.g. the Models group, the Room
# group, the Settings group). We look for a group whose name matches.
FILES_TO_ADD = [
    ("Plink/Models/BubbleStyle.swift", "Models"),
    ("Plink/Views/Room/StyledChatBubble.swift", "Room"),
    ("Plink/Views/Settings/ChatAppearanceSheet.swift", "Settings"),
    ("Plink/Views/Settings/BubbleStylePickerSheet.swift", "Settings"),
]

def gen_id():
    """Generate a 24-char hex UUID matching Xcode's pbxproj ID format."""
    return uuid.uuid4().hex[:24].upper()

def main():
    if not PBXPROJ.exists():
        print(f"ERROR: pbxproj not found at {PBXPROJ}")
        sys.exit(1)

    content = PBXPROJ.read_text(encoding="utf-8")
    original = content

    for rel_path, group_hint in FILES_TO_ADD:
        filename = Path(rel_path).name
        basename = Path(rel_path).stem

        # Idempotency check: skip if already referenced
        if f'"{filename}"' in content and (
            f'/{rel_path}"' in content or f'/{filename}"' in content
        ):
            # Verify it's actually in PBXBuildFile section (not just a comment)
            if filename in content:
                print(f"SKIP (already in pbxproj): {rel_path}")
                continue

        print(f"Adding: {rel_path} → group '{group_hint}'")

        file_ref_id = gen_id()
        build_file_id = gen_id()

        # ─── 1. PBXFileReference section ────────────────────────────────
        # Format: <id> /* filename.swift */ = {isa = PBXFileReference;
        #   fileEncoding = 4; lastKnownFileType = sourcecode.swift;
        #   path = filename.swift; sourceTree = "<group>"; };
        #
        # path = filename.swift (relative to its parent group's path)
        # If the parent group has a path (e.g. "Plink/Models"), then
        # file ref path is just the filename. We use the filename only.
        file_ref_entry = (
            f'\t\t{file_ref_id} /* {filename} */ = {{isa = PBXFileReference; '
            f'fileEncoding = 4; lastKnownFileType = sourcecode.swift; '
            f'path = "{filename}"; sourceTree = "<group>"; }};\n'
        )

        # Insert into PBXFileReference section (before the closing brace)
        # Find the section by marker
        file_ref_section_end = content.find("/* End PBXFileReference section */")
        if file_ref_section_end == -1:
            print(f"ERROR: PBXFileReference section not found")
            sys.exit(1)
        content = content[:file_ref_section_end] + file_ref_entry + content[file_ref_section_end:]

        # ─── 2. PBXBuildFile section ────────────────────────────────────
        # Format: <id> /* filename.swift in Sources */ = {isa = PBXBuildFile;
        #   fileRef = <file_ref_id> /* filename.swift */; };
        build_file_entry = (
            f'\t\t{build_file_id} /* {filename} in Sources */ = {{isa = PBXBuildFile; '
            f'fileRef = {file_ref_id} /* {filename} */; }};\n'
        )

        build_file_section_end = content.find("/* End PBXBuildFile section */")
        if build_file_section_end == -1:
            print(f"ERROR: PBXBuildFile section not found")
            sys.exit(1)
        content = content[:build_file_section_end] + build_file_entry + content[build_file_section_end:]

        # ─── 3. PBXGroup — add fileRef to the parent group's children ───
        # Find a group whose name contains the group_hint AND has children.
        # Group format:
        #   <id> /* GroupName */ = {
        #       isa = PBXGroup;
        #       children = (
        #           <child_id> /* child.swift */,
        #           ...
        #       );
        #       path = "Plink/Models";  (or name = "Models"; if virtual)
        #       sourceTree = "<group>";
        #   };
        #
        # We add our fileRef as a new child entry in the children array.
        # Strategy: find all PBXGroup blocks, pick the one whose name/path
        # contains the group_hint, and insert our child into its children list.

        # Find the group block by searching for "/* <hint> */ = {\n\t\t\tisa = PBXGroup;"
        # Group names appear as comments like /* Models */ or /* Room */
        group_pattern = re.compile(
            r'([0-9A-F]{24}) /\* (' + re.escape(group_hint) + r'\w*) \*/ = \{\s*'
            r'isa = PBXGroup;\s*'
            r'children = \(',
            re.IGNORECASE
        )
        match = group_pattern.search(content)
        if not match:
            # Fallback: try matching by path containing the hint
            group_pattern2 = re.compile(
                r'([0-9A-F]{24}) /\* (\w+) \*/ = \{\s*'
                r'isa = PBXGroup;\s*'
                r'children = \(',
                re.IGNORECASE
            )
            for m in group_pattern2.finditer(content):
                # Check if this group's path/name contains the hint
                # Look ahead 500 chars to find path = or name =
                start = m.end()
                block = content[start:start+500]
                if f'path = "{group_hint}' in block or f'name = "{group_hint}' in block or f'path = "Plink/{group_hint}' in block:
                    match = m
                    break

        if not match:
            print(f"  WARNING: could not find PBXGroup matching '{group_hint}'. "
                  f"File will be added to build but not visible in Xcode navigator.")
        else:
            # Insert our fileRef as first child in the children list
            children_start = match.end()
            child_entry = f'\n\t\t\t\t{file_ref_id} /* {filename} */,'
            content = content[:children_start] + child_entry + content[children_start:]

        # ─── 4. PBXSourcesBuildPhase — add buildFile to Sources ─────────
        # Format in build phase:
        #   files = (
        #       <id> /* filename.swift in Sources */,
        #       ...
        #   );
        sources_phase_pattern = re.compile(
            r'isa = PBXSourcesBuildPhase;\s*'
            r'buildActionMask = \d+;\s*'
            r'files = \(',
            re.IGNORECASE
        )
        sources_match = sources_phase_pattern.search(content)
        if not sources_match:
            print(f"  WARNING: PBXSourcesBuildPhase not found — file won't compile")
        else:
            files_start = sources_match.end()
            build_entry = f'\n\t\t\t\t{build_file_id} /* {filename} in Sources */,'
            content = content[:files_start] + build_entry + content[files_start:]

        print(f"  ✓ Added {filename} (fileRef={file_ref_id}, buildFile={build_file_id})")

    if content == original:
        print("\nNo changes needed — all files already in pbxproj.")
    else:
        PBXPROJ.write_text(content, encoding="utf-8")
        print(f"\n✓ Updated {PBXPROJ}")
        print(f"  Added {len(FILES_TO_ADD)} files to Xcode project.")

if __name__ == "__main__":
    main()
