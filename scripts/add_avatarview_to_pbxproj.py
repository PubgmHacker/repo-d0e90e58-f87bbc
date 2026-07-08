#!/usr/bin/env python3
"""
Add AvatarView.swift to Plink.xcodeproj/project.pbxproj.

AvatarView.swift физически лежит в Plink/Views/Components/, но отсутствует в pbxproj.
Без этого Xcode не видит ни AvatarView, ни AdminBadgeChip (defined в том же файле).

Используем тот же паттерн что и для других Components файлов:
- PBXBuildFile entry
- PBXFileReference entry
- Group children entry (рядом с BioluminescentBackground.swift)
- Sources phase entry
"""
import sys
from pathlib import Path

PBXPROJ = "/tmp/plink-ios-push/Plink.xcodeproj/project.pbxproj"

# Уникальные 24-символьные hex ID (не должны конфликтовать с существующими)
BUILD_FILE_ID = "B1C2D3E4F5A6B7C8D9E0F1A2"  # AvatarView BuildFile
FILE_REF_ID   = "C2D3E4F5A6B7C8D9E0F1A2B3"  # AvatarView FileReference

content = Path(PBXPROJ).read_text()

if "AvatarView.swift" in content:
    print("AvatarView.swift already in pbxproj — skipping")
    sys.exit(0)

# 1. PBXBuildFile — вставляем после AnimatedGradientBackground.swift BuildFile
build_file_line = f"\t\t{BUILD_FILE_ID} /* AvatarView.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {FILE_REF_ID} /* AvatarView.swift */; }};\n"
anim_build_line = "\t\tDE418B80C765488E66A43D20 /* AnimatedGradientBackground.swift in Sources */ = {isa = PBXBuildFile; fileRef = 2FF278F889A3C7FDC2BFAE09 /* AnimatedGradientBackground.swift */; };\n"
if anim_build_line not in content:
    print("ERROR: AnimatedGradientBackground BuildFile line not found")
    sys.exit(1)
content = content.replace(anim_build_line, anim_build_line + build_file_line, 1)

# 2. PBXFileReference — после AnimatedGradientBackground.swift FileReference
file_ref_line = f"\t\t{FILE_REF_ID} /* AvatarView.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = AvatarView.swift; sourceTree = \"<group>\"; }};\n"
anim_ref_line = "\t\t2FF278F889A3C7FDC2BFAE09 /* AnimatedGradientBackground.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = AnimatedGradientBackground.swift; sourceTree = \"<group>\"; };\n"
if anim_ref_line not in content:
    print("ERROR: AnimatedGradientBackground FileReference line not found")
    sys.exit(1)
content = content.replace(anim_ref_line, anim_ref_line + file_ref_line, 1)

# 3. Group children — после AnimatedGradientBackground.swift в группе Components
group_line = f"\t\t\t\t{FILE_REF_ID} /* AvatarView.swift */,\n"
anim_group_line = "\t\t\t\t2FF278F889A3C7FDC2BFAE09 /* AnimatedGradientBackground.swift */,\n"
if anim_group_line not in content:
    print("ERROR: AnimatedGradientBackground group line not found")
    sys.exit(1)
content = content.replace(anim_group_line, anim_group_line + group_line, 1)

# 4. Sources build phase — после AnimatedGradientBackground.swift in Sources
sources_line = f"\t\t\t\t{BUILD_FILE_ID} /* AvatarView.swift in Sources */,\n"
anim_sources_line = "\t\t\t\tDE418B80C765488E66A43D20 /* AnimatedGradientBackground.swift in Sources */,\n"
if anim_sources_line not in content:
    print("ERROR: AnimatedGradientBackground Sources line not found")
    sys.exit(1)
content = content.replace(anim_sources_line, anim_sources_line + sources_line, 1)

Path(PBXPROJ).write_text(content)
print("✓ Added AvatarView.swift to pbxproj (4 insertions)")
