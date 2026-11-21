#!/usr/bin/env python3
import subprocess
import os
import tempfile
import sys

repo_root = "/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject"
agent_dir = f"{repo_root}/.agents/teamwork/explorer_m4_it2_1"

def verify():
    remediation_path = f"{repo_root}/MyOfflineMapApp/Tests/MyOfflineMapAppTests/RemediationTests.swift"
    with open(remediation_path) as f:
        lines = f.readlines()

    # Preprocess lines to stub imports not available in CommandLineTools
    mod_lines = list(lines)
    for i in range(10):
        l = mod_lines[i].strip()
        if l.startswith("import XCTest") or l.startswith("import MapLibre") or l.startswith("import Valhalla") or l.startswith("@testable import"):
            mod_lines[i] = "// " + mod_lines[i]

    tmp_path = "/tmp/remediation_typecheck_tmp.swift"
    with open(tmp_path, "w") as tmp:
        tmp.writelines(mod_lines)

    try:
        cmd = [
            "swiftc",
            "-module-cache-path", "/tmp/clang-cache",
            "-typecheck",
            "-parse-as-library",
            f"{repo_root}/MyOfflineMapApp/Sources/NavigationViewModel.swift",
            f"{agent_dir}/MockEnvironment.swift",
            tmp_path
        ]
        res = subprocess.run(cmd, env={**os.environ, "TMPDIR": "/tmp"}, capture_output=True, text=True)
        errors = [l for l in res.stderr.splitlines() if "error:" in l]
        
        print(f"Compilation Return Code: {res.returncode}")
        print(f"Total Errors Found: {len(errors)}")
        for e in errors:
            print(f"  {e}")

        if res.returncode == 0 and len(errors) == 0:
            print("SUCCESS: RemediationTests.swift compiles with 0 errors!")
            return 0
        else:
            print("FAILURE: RemediationTests.swift has compilation errors.")
            return 1
    finally:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)

if __name__ == "__main__":
    sys.exit(verify())
