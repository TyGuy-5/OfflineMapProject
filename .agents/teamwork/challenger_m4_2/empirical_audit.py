#!/usr/bin/env python3
import subprocess
import os
import re
import sys

def run():
    repo_root = "/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject"
    os.chdir(repo_root)

    print("=== EMPIRICAL AUDIT START ===")

    # 1. Get git tracked files
    tracked_files = subprocess.check_output(["git", "ls-files"], text=True).splitlines()
    print(f"Total git tracked files: {len(tracked_files)}")

    # 2. Check for '/Volumes/Extended Hard Drive' or local machine UDIDs in tracked files
    known_bad_udid = "0A20D9A5-C44D-4D07-89E0-F1F0B2FE5CFE"
    uuid_pattern = re.compile(r"\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\b")
    
    path_violations = []
    udid_violations = []

    for fpath in tracked_files:
        # Skip large files or binaries if any
        if os.path.getsize(fpath) > 10 * 1024 * 1024:
            continue
        try:
            with open(fpath, "r", encoding="utf-8", errors="ignore") as f:
                content = f.read()
                lines = content.splitlines()
                for line_no, line in enumerate(lines, 1):
                    if "/Volumes/Extended Hard Drive" in line:
                        path_violations.append((fpath, line_no, line.strip()))
                    if known_bad_udid.lower() in line.lower():
                        udid_violations.append((fpath, line_no, line.strip()))
        except Exception as e:
            print(f"Error reading {fpath}: {e}")

    print(f"Tracked files with '/Volumes/Extended Hard Drive': {len(path_violations)}")
    for v in path_violations:
        print(f"  {v[0]}:{v[1]}: {v[2]}")

    print(f"Tracked files with simulator UDID ({known_bad_udid}): {len(udid_violations)}")
    for v in udid_violations:
        print(f"  {v[0]}:{v[1]}: {v[2]}")

    # 3. Explicit check on DOCUMENTATION.md and docs/AUDIT_REPORT.md
    doc_files = ["DOCUMENTATION.md", "docs/AUDIT_REPORT.md"]
    doc_path_violations = []
    doc_uuid_matches = []
    for df in doc_files:
        if not os.path.exists(df):
            print(f"CRITICAL: {df} does not exist!")
            continue
        with open(df, "r", encoding="utf-8") as f:
            for line_no, line in enumerate(f, 1):
                if "/Volumes/Extended Hard Drive" in line or "Mac Mini M4" in line:
                    doc_path_violations.append((df, line_no, line.strip()))
                uuids = uuid_pattern.findall(line)
                if uuids:
                    doc_uuid_matches.append((df, line_no, uuids, line.strip()))

    print(f"\nDOCUMENTATION / AUDIT_REPORT hardcoded machine path violations: {len(doc_path_violations)}")
    for v in doc_path_violations:
        print(f"  {v[0]}:{v[1]}: {v[2]}")

    print(f"DOCUMENTATION / AUDIT_REPORT UUID occurrences: {len(doc_uuid_matches)}")
    for v in doc_uuid_matches:
        print(f"  {v[0]}:{v[1]} UUIDs={v[2]}: {v[3]}")

    # 4. #filePath count check
    # MyOfflineMapApp/Sources/OfflineDataManager.swift == 1
    # MyOfflineMapApp/Tests/MyOfflineMapAppTests/RemediationTests.swift == 0
    odm_path = "MyOfflineMapApp/Sources/OfflineDataManager.swift"
    rem_path = "MyOfflineMapApp/Tests/MyOfflineMapAppTests/RemediationTests.swift"

    with open(odm_path, "r", encoding="utf-8") as f:
        odm_filepath_count = sum(line.count("#filePath") for line in f)
    with open(rem_path, "r", encoding="utf-8") as f:
        rem_filepath_count = sum(line.count("#filePath") for line in f)

    print(f"\n#filePath in {odm_path}: {odm_filepath_count} (Expected: 1)")
    print(f"#filePath in {rem_path}: {rem_filepath_count} (Expected: 0)")

    # 5. ValhallaConfigModels occurrences across entire project
    print("\nScanning for 'ValhallaConfigModels' across repo...")
    vcm_matches = []
    for root, dirs, files in os.walk(repo_root):
        if any(skip in root for skip in [".git", ".agents", "data"]):
            continue
        for fname in files:
            fpath = os.path.join(root, fname)
            if os.path.getsize(fpath) > 5 * 1024 * 1024:
                continue
            relpath = os.path.relpath(fpath, repo_root)
            try:
                with open(fpath, "r", encoding="utf-8", errors="ignore") as f:
                    for line_no, line in enumerate(f, 1):
                        if "ValhallaConfigModels" in line:
                            vcm_matches.append((relpath, line_no, line.strip()))
            except Exception:
                pass

    print(f"ValhallaConfigModels matches outside .git/.agents/data: {len(vcm_matches)}")
    for m in vcm_matches:
        print(f"  {m[0]}:{m[1]}: {m[2]}")

    # 6. Check ContentView in RemediationTests.swift
    with open(rem_path, "r", encoding="utf-8") as f:
        rem_cv_matches = [(idx, line.strip()) for idx, line in enumerate(f, 1) if "ContentView" in line]
    print(f"\nContentView occurrences in {rem_path}: {len(rem_cv_matches)} (Expected: 0)")
    for m in rem_cv_matches:
        print(f"  Line {m[0]}: {m[1]}")

    print("=== EMPIRICAL AUDIT COMPLETE ===")

if __name__ == "__main__":
    run()
