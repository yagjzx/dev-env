#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

SKIP_DIRS = {
    ".git",
    "node_modules",
    ".venv",
    "venv",
    "__pycache__",
    ".pytest_cache",
    ".mypy_cache",
    ".ruff_cache",
    ".next",
    "dist",
    "build",
    "coverage",
    ".turbo",
    ".idea",
    ".vscode",
    "target",
    "vendor",
    ".cache",
    ".gradle",
    ".pnpm-store",
    ".yarn",
    ".parcel-cache",
    ".svelte-kit",
}

SKIP_EXTS = {
    ".png",
    ".jpg",
    ".jpeg",
    ".gif",
    ".webp",
    ".pdf",
    ".mp3",
    ".mp4",
    ".wav",
    ".mov",
    ".zip",
    ".tar",
    ".gz",
    ".onnx",
    ".bin",
    ".pt",
    ".pth",
    ".ckpt",
    ".safetensors",
    ".npy",
    ".flac",
    ".ttf",
    ".ibgzenc",
    ".dat",
    ".ico",
    ".svg",
    ".pbtxt",
}

MANIFEST_CHECKS = [
    ("pyproject.toml", "pyproject"),
    ("package.json", "package.json"),
    ("go.mod", "go.mod"),
    ("Cargo.toml", "Cargo.toml"),
    ("docker-compose.yml", "docker-compose.yml"),
    ("docker-compose.yaml", "docker-compose.yaml"),
    ("Dockerfile", "Dockerfile"),
    ("CLAUDE.md", "CLAUDE.md"),
    ("AGENTS.md", "AGENTS.md"),
    ("README.md", "README.md"),
]


def scan_repo(repo: Path) -> dict[str, object]:
    file_count = 0
    line_count = 0
    exts: Counter[str] = Counter()

    for dirpath, dirnames, filenames in os.walk(repo):
        dirnames[:] = [name for name in dirnames if name not in SKIP_DIRS]
        for filename in filenames:
            path = Path(dirpath) / filename
            if any(part in SKIP_DIRS for part in path.parts):
                continue
            ext = path.suffix.lower()
            if ext in SKIP_EXTS:
                continue
            file_count += 1
            exts[ext or "[no-ext]"] += 1
            try:
                with path.open("r", encoding="utf-8", errors="ignore") as handle:
                    line_count += sum(1 for _ in handle)
            except OSError:
                pass

    manifests = [label for rel, label in MANIFEST_CHECKS if (repo / rel).exists()]
    return {
        "name": repo.name,
        "files": file_count,
        "lines": line_count,
        "top_exts": ", ".join(f"{ext}:{count}" for ext, count in exts.most_common(5)),
        "manifests": ", ".join(manifests) if manifests else "-",
        "exts": exts,
    }


def render_markdown(workspace: Path, rows: list[dict[str, object]]) -> str:
    overall_files = sum(int(row["files"]) for row in rows)
    overall_lines = sum(int(row["lines"]) for row in rows)
    overall_exts: Counter[str] = Counter()
    for row in rows:
        overall_exts.update(row["exts"])  # type: ignore[arg-type]

    output: list[str] = []
    output.append("# Workspace Scan")
    output.append("")
    output.append(f"Generated: {datetime.now(timezone.utc).isoformat()}")
    output.append("")
    output.append("## Summary")
    output.append("")
    output.append(f"- Workspace: {workspace}")
    output.append(f"- Repositories scanned: {len(rows)}")
    output.append(f"- Text/code files scanned: {overall_files}")
    output.append(f"- Approximate text/code lines scanned: {overall_lines}")
    output.append(
        "- Top file extensions: "
        + ", ".join(f"{ext}:{count}" for ext, count in overall_exts.most_common(12))
    )
    output.append("")
    output.append("## Repository Inventory")
    output.append("")
    output.append("| Repo | Files | Lines | Top file types | Key files |")
    output.append("| --- | ---: | ---: | --- | --- |")
    for row in rows:
        output.append(
            "| {name} | {files} | {lines} | {top_exts} | {manifests} |".format(**row)
        )
    output.append("")
    output.append("## Notes")
    output.append("")
    output.append(
        "- This scan is a workspace-wide structural pass across all local repositories and text files, excluding obvious vendored/generated directories such as .git, node_modules, .venv, dist, build, and caches."
    )
    output.append(
        "- It is intended as a full local inventory baseline, not a line-by-line semantic code review of every repository."
    )
    output.append("")
    return "\n".join(output)


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate a workspace-wide scan report.")
    parser.add_argument("--workspace", default="/workspace")
    parser.add_argument("--output", default="/workspace/WORKSPACE_SCAN.md")
    args = parser.parse_args()

    workspace = Path(args.workspace).resolve()
    repos = sorted(path for path in workspace.iterdir() if (path / ".git").exists())
    rows = [scan_repo(repo) for repo in repos]
    markdown = render_markdown(workspace, rows)

    output = Path(args.output)
    output.write_text(markdown, encoding="utf-8")
    print(output)
    print(f"repos={len(rows)} files={sum(int(row['files']) for row in rows)} lines={sum(int(row['lines']) for row in rows)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
