#!/usr/bin/env python3
"""Publish a tested main commit using the manifest version and changelog notes."""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess


def release_notes(root):
    version = json.loads((root / "manifest.json").read_text())["version"]
    if not isinstance(version, str) or not re.fullmatch(r"(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)", version):
        raise ValueError("Release version must be a stable major.minor.patch version")
    changelog = (root / "CHANGELOG.md").read_text()
    headings = list(re.finditer(r"^## (.+)$", changelog, re.MULTILINE))
    if not headings or headings[0][1].split(" — ")[0] != version:
        raise ValueError("The newest changelog entry must match manifest.json")
    end = headings[1].start() if len(headings) > 1 else len(changelog)
    notes = changelog[headings[0].end():end].strip()
    if not notes:
        raise ValueError("Release notes must not be empty")
    return "v" + version, notes


def github(method, path, payload=None):
    command = ["gh", "api", "--method", method, path]
    if payload is not None:
        command.extend(["--input", "-"])
    result = subprocess.run(command, input=json.dumps(payload) if payload is not None else None,
                            capture_output=True, text=True, timeout=60)
    if result.returncode:
        if method == "GET" and "(HTTP 404)" in result.stderr:
            return None
        raise RuntimeError(result.stderr.strip() or "GitHub API request failed")
    return json.loads(result.stdout)


def publish(repo, commit, tag, notes, api=github):
    if not re.fullmatch(r"[\w.-]+/[\w.-]+", repo) or not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise ValueError("Publishing requires a repository and full tested commit SHA")
    base = "repos/" + repo
    head = api("GET", base + "/git/ref/heads/main")
    if not head:
        raise RuntimeError("Cannot resolve main")
    if head["object"]["sha"] != commit:
        return "Skipped: main advanced beyond this tested commit"
    release = api("GET", base + "/releases/tags/" + tag)
    if release:
        if release["draft"]:
            raise RuntimeError("A draft already exists; review it before publishing")
        return "Already published: " + release["html_url"]
    ref = api("GET", base + "/git/ref/tags/" + tag)
    if ref:
        target = ref["object"]
        # Resolve annotated tags as well as lightweight tags.
        for _ in range(4):
            if target["type"] != "tag":
                break
            annotation = api("GET", base + "/git/tags/" + target["sha"])
            if not annotation:
                raise RuntimeError("Cannot resolve release tag")
            target = annotation["object"]
        if target["type"] != "commit" or target["sha"] != commit:
            raise RuntimeError("Existing tag does not identify the tested commit")
    release = api("POST", base + "/releases", {
        "tag_name": tag, "target_commitish": commit,
        "name": "Localhost " + tag, "body": notes,
        "draft": False, "prerelease": False, "make_latest": "true",
    })
    return "Published: " + release["html_url"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--publish", action="store_true", help="publish after CI passes on main")
    args = parser.parse_args()
    tag, notes = release_notes(Path(__file__).resolve().parent.parent)
    if args.publish:
        print(publish(os.environ.get("GITHUB_REPOSITORY", ""), os.environ.get("GITHUB_SHA", ""), tag, notes))
    else:
        print(f"Release notes validated for {tag}")


if __name__ == "__main__":
    main()
