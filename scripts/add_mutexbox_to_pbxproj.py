#!/usr/bin/env python3
"""
Add MutexBox.swift to Plink.xcodeproj/project.pbxproj.

Adds the file in 4 places (matching OrientationManager.swift pattern):
1. PBXBuildFile section — links file to Sources phase
2. PBXFileReference section — declares the file
3. Group children — adds to Utilities group
4. Sources build phase — includes in compilation
"""
import re
import sys
from pathlib import Path

PBXPROJ = "/tmp/plink-ios-push/Plink.xcodeproj/project.pbxproj"

# Generate stable-looking unique IDs (24 hex chars)
BUILD_FILE_ID = "A1B2C3D4E5F6A7B8C9D0E1F2"  # MutexBox BuildFile
FILE_REF_ID   = "F1E2D3C4B5A6978879605140"  # MutexBox FileReference

# Read existing
content = Path(PBXPROJ).read_text()

# 1. Add PBXBuildFile entry — insert after OrientationManager.swift BuildFile line
build_file_line = f"\t\t{BUILD_FILE_ID} /* MutexBox.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {FILE_REF_ID} /* MutexBox.swift */; }};\n"
orientation_build_line = "\t\t12226B2D7E22DCB80D5CE504 /* OrientationManager.swift in Sources */ = {isa = PBXBuildFile; fileRef = D4788A753344D8F34B3BA20B /* OrientationManager.swift */; };\n"
if "MutexBox.swift" in content:
    print("MutexBox.swift already in pbxproj — skipping")
    sys.exit(0)
if orientation_build_line not in content:
    print("ERROR: OrientationManager build file line not found")
    sys.exit(1)
content = content.replace(orientation_build_line, orientation_build_line + build_file_line)

# 2. Add PBXFileReference entry — after OrientationManager.swift FileReference
file_ref_line = f"\t\t{FILE_REF_ID} /* MutexBox.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = MutexBox.swift; sourceTree = \"<group>\"; }};\n"
orientation_ref_line = "\t\tD4788A753344D8F34B3BA20B /* OrientationManager.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = OrientationManager.swift; sourceTree = \"<group>\"; };\n"
if orientation_ref_line not in content:
    print("ERROR: OrientationManager FileReference line not found")
    sys.exit(1)
content = content.replace(orientation_ref_line, orientation_ref_line + file_ref_line, 1)

# 3. Add to Utilities group children — after OrientationManager.swift group entry
group_line = f"\t\t\t\t{FILE_REF_ID} /* MutexBox.swift */,\n"
orientation_group_line = "\t\t\t\tD4788A753344D8F34B3BA20B /* OrientationManager.swift */,\n"
if orientation_group_line not in content:
    print("ERROR: OrientationManager group line not found")
    sys.exit(1)
content = content.replace(orientation_group_line, orientation_group_line + group_line, 1)

# 4. Add to Sources build phase — after OrientationManager.swift in Sources entry
sources_line = f"\t\t\t\t{BUILD_FILE_ID} /* MutexBox.swift in Sources */,\n"
orientation_sources_line = "\t\t\t\t12226B2D7E22DCB80D5CE504 /* OrientationManager.swift in Sources */,\n"
if orientation_sources_line not in content:
    print("ERROR: OrientationManager Sources line not found")
    sys.exit(1)
content = content.replace(orientation_sources_line, orientation_sources_line + sources_line, 1)

# Write back
Path(PBXPROJ).write_text(content)
print("✓ Added MutexBox.swift to pbxproj (4 insertions)")
