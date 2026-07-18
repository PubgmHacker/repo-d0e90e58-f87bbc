#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Plink rollback - revert ALL my recent changes back to aba02eaa.

Reverts 6 commits (5dfe13ee..19fc90fb) which added:
- 5dfe13ee: REAL fixes for player loading, Offline pill, voice bubble, flicker, warnings
- 9c4053c2: DM flicker (quiet:true polling) + diagnostic logs for player offline
- 45567817: default state .connecting + drop friends poll + voice logs
- c541c247: try? for evaluateJavaScript in handleReady diagnostic
- d667c109: YouTube tap-to-play + friends poll 10s + voice bubble style
- 19fc90fb: YouTube mute:1 force-recreate + poll 6s/10s + voice bubble currentID

User reported all fixes did not work and want to revert to state before my
changes (aba02eaa).

Usage:
    cd /Users/hellcart/Desktop/Grok
    python3 apply_plink_rollback.py
"""
import os
import subprocess

PROJECT = os.getcwd()


def git(args, check=True):
    """Run a git command in PROJECT."""
    result = subprocess.run(
        ["git"] + args,
        cwd=PROJECT,
        capture_output=True,
        text=True
    )
    if check and result.returncode != 0:
        print(f"  [ERR] git {' '.join(args)}")
        print(f"        stderr: {result.stderr}")
        raise SystemExit(1)
    return result.stdout.strip()


def confirm():
    print("=" * 60)
    print("ROLLBACK: Reverting ALL recent Plink fixes")
    print("=" * 60)
    print()
    print("This will:")
    print("  1. Reset 5 Swift files to their state at commit aba02eaa")
    print("     (last commit before my changes)")
    print("  2. Leave apply_plink_*.py scripts alone (they're not Swift)")
    print("  3. Create a NEW commit 'revert: rollback to aba02eaa state'")
    print("  4. NOT push automatically - you push when ready")
    print()
    print("Files that will be reset to aba02eaa:")
    print("  - Plink/Services/PlinkPermissions.swift")
    print("  - Plink/Features/WatchRoom/PlayerControlLayer.swift")
    print("  - Plink/Services/DMChatService.swift")
    print("  - Plink/V4/PlinkApprovedV4Root.swift")
    print("  - Plink/Views/Chat/DMChatView.swift")
    print("  - Plink/Playback/EmbeddedPlaybackController.swift")
    print("  - Plink/Features/WatchRoom/WatchRoomModel.swift")
    print("  - Plink/Realtime/RealtimeClient.swift")
    print("  - Plink/V4/V4FriendsView.swift")
    print("  - Plink/Features/WatchRoom/PlayerStage.swift")
    print()
    print("Proceeding in 2 seconds... (Ctrl+C to abort)")
    print()
    import time
    time.sleep(2)


def main():
    confirm()

    # Files that were modified by my recent commits
    files_to_revert = [
        "Plink/Services/PlinkPermissions.swift",
        "Plink/Features/WatchRoom/PlayerControlLayer.swift",
        "Plink/Services/DMChatService.swift",
        "Plink/V4/PlinkApprovedV4Root.swift",
        "Plink/Views/Chat/DMChatView.swift",
        "Plink/Playback/EmbeddedPlaybackController.swift",
        "Plink/Features/WatchRoom/WatchRoomModel.swift",
        "Plink/Realtime/RealtimeClient.swift",
        "Plink/V4/V4FriendsView.swift",
        "Plink/Features/WatchRoom/PlayerStage.swift",
    ]

    print("[1/3] Checking current state...")
    current_commit = git(["rev-parse", "HEAD"])
    print(f"  Current HEAD: {current_commit[:8]}")

    # Verify aba02eaa exists
    git(["cat-file", "-t", "aba02eaa"])

    print()
    print("[2/3] Resetting Swift files to aba02eaa state...")
    for f in files_to_revert:
        # Check if file exists at aba02eaa
        result = subprocess.run(
            ["git", "cat-file", "-e", f"aba02eaa:{f}"],
            cwd=PROJECT,
            capture_output=True
        )
        if result.returncode != 0:
            print(f"  [SKIP] {f} - does not exist at aba02eaa")
            continue

        # Restore file from aba02eaa
        result = subprocess.run(
            ["git", "checkout", "aba02eaa", "--", f],
            cwd=PROJECT,
            capture_output=True,
            text=True
        )
        if result.returncode == 0:
            print(f"  [OK]   {f}")
        else:
            print(f"  [ERR]  {f}: {result.stderr.strip()}")

    print()
    print("[3/3] Staging + committing rollback...")
    git(["add"] + files_to_revert)
    git(["commit", "-m",
         "revert: rollback to aba02eaa state\n\n"
         "User reported all recent fixes did not work:\n"
         "- Player still stuck in state=3 (YouTube buffering)\n"
         "- Flicker on long-press still present\n"
         "- Voice bubble still turquoise (not matching style)\n\n"
         "Reverting ALL my recent commits back to aba02eaa:\n"
         "- 5dfe13ee: REAL fixes for player loading, Offline pill, voice bubble, flicker, warnings\n"
         "- 9c4053c2: DM flicker (quiet:true polling) + diagnostic logs for player offline\n"
         "- 45567817: default state .connecting + drop friends poll + voice logs\n"
         "- c541c247: try? for evaluateJavaScript in handleReady diagnostic\n"
         "- d667c109: YouTube tap-to-play + friends poll 10s + voice bubble style\n"
         "- 19fc90fb: YouTube mute:1 force-recreate + poll 6s/10s + voice bubble currentID\n\n"
         "Code is now back to the state user was testing before my changes."])

    print()
    print("=" * 60)
    print("DONE. Rollback committed locally.")
    print("=" * 60)
    print()
    print("To push:")
    print("  git push origin main")
    print()
    print("To verify what was reverted:")
    print("  git show --stat HEAD")
    print()
    print("After push:")
    print("  1. In Xcode: Cmd+Shift+K (Clean Build Folder)")
    print("  2. Cmd+B (Build)")
    print("  3. Cmd+R (Run)")
    print()
    print("App should now behave EXACTLY like before my changes.")
    print("If you want me to try different fixes, please describe what")
    print("exactly you want fixed and I'll start fresh.")
    print("=" * 60)


if __name__ == "__main__":
    main()
