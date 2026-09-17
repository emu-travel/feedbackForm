"""Build the production deployment folder for the feedback release.

  python release/scripts/build_release.py

1. Converts everything named in release/package.xml from force-app to metadata
   format, in release/build.
2. Puts in the production settings record (release/production), so the build
   carries the production survey address and start date, not staging's.
3. Removes staging's content keys from the site bundle, which production does
   not know.
4. Adds the prepared changes to production's own metadata (release/org-changes)
   and merges their manifest in.
5. Refuses to finish if anything in the build still points at staging.

The result is validated check-only with sf project deploy validate --metadata-dir
release/build, and deployed with sf project deploy quick on go-live day.
"""

import glob
import json
import os
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
RELEASE = os.path.join(ROOT, "release")
BUILD = os.path.join(RELEASE, "build")
NS = "http://soap.sforce.com/2006/04/metadata"
ET.register_namespace("", NS)


def q(tag):
    return "{%s}%s" % (NS, tag)


def run(cmd):
    print(">", cmd)
    done = subprocess.run(cmd, shell=True, cwd=ROOT, capture_output=True, text=True)
    if done.returncode != 0:
        print(done.stdout[-3000:], done.stderr[-3000:])
        raise SystemExit(f"failed: {cmd}")


def main():
    org_changes = os.path.join(RELEASE, "org-changes")
    if not os.path.isfile(os.path.join(org_changes, "package.xml")):
        raise SystemExit("release/org-changes is missing: run release/scripts/prepare_org_changes.py first")

    shutil.rmtree(BUILD, ignore_errors=True)
    run('sf project convert source --manifest release/package.xml --output-dir release/build')

    # 2. Production settings.
    settings = os.path.join(BUILD, "customMetadata", "Gx_Feedback_Setting.Default.md")
    if not os.path.isfile(settings):
        raise SystemExit("the build has no Gx_Feedback_Setting.Default record")
    shutil.copyfile(os.path.join(RELEASE, "production", "Gx_Feedback_Setting.Default.md-meta.xml"), settings)
    print("settings: production record in place")

    # 3. Staging's content keys out of the site bundle.
    stripped = 0
    for meta in glob.glob(os.path.join(BUILD, "digitalExperiences", "**", "_meta.json"), recursive=True):
        with open(meta, encoding="utf-8") as fh:
            data = json.load(fh)
        if "contentKey" in data:
            del data["contentKey"]
            stripped += 1
            with open(meta, "w", encoding="utf-8", newline="\n") as fh:
                json.dump(data, fh, indent=2)
                fh.write("\n")
    print(f"site bundle: {stripped} staging content keys removed")

    # 4. Production's own metadata, and one manifest for both.
    for path in glob.glob(os.path.join(org_changes, "**", "*"), recursive=True):
        rel = os.path.relpath(path, org_changes)
        if os.path.isdir(path) or rel == "package.xml":
            continue
        target = os.path.join(BUILD, rel)
        if os.path.exists(target) and rel.endswith(".object"):
            # The release adds new fields to the same object: one file, with
            # production's field placed after the release's own.
            with open(path, encoding="utf-8") as fh:
                extra = re.findall(r"    <fields>.*?</fields>\n", fh.read(), re.S)
            with open(target, encoding="utf-8") as fh:
                text = fh.read()
            for block in extra:
                name = re.search(r"<fullName>([^<]*)</fullName>", block).group(1)
                if f"<fullName>{name}</fullName>" in text:
                    raise SystemExit(f"{rel}: {name} is both in the release and in org-changes")
            last = text.rfind("</fields>\n") + len("</fields>\n")
            with open(target, "w", encoding="utf-8", newline="\n") as fh:
                fh.write(text[:last] + "".join(extra) + text[last:])
            print(f"{rel}: merged {len(extra)} field(s) from org-changes")
            continue
        if os.path.exists(target):
            raise SystemExit(f"{rel} is both in the release and in org-changes")
        os.makedirs(os.path.dirname(target), exist_ok=True)
        shutil.copyfile(path, target)

    main_tree = ET.parse(os.path.join(BUILD, "package.xml"))
    main_root = main_tree.getroot()
    by_name = {t.find(q("name")).text: t for t in main_root.findall(q("types"))}
    for t in ET.parse(os.path.join(org_changes, "package.xml")).getroot().findall(q("types")):
        name = t.find(q("name")).text
        target = by_name.get(name)
        if target is None:
            target = ET.SubElement(main_root, q("types"))
            ET.SubElement(target, q("name")).text = name
            by_name[name] = target
        existing = {m.text for m in target.findall(q("members"))}
        for m in t.findall(q("members")):
            if m.text not in existing:
                member = ET.Element(q("members"))
                member.text = m.text
                target.insert(0, member)
    # Types sorted by name, members sorted, <name> last, <version> at the end.
    version = main_root.find(q("version"))
    main_root.remove(version)
    types = sorted(main_root.findall(q("types")), key=lambda t: t.find(q("name")).text)
    for t in list(main_root):
        main_root.remove(t)
    for t in types:
        name = t.find(q("name")).text
        members = sorted(m.text for m in t.findall(q("members")))
        for child in list(t):
            t.remove(child)
        for m in members:
            ET.SubElement(t, q("members")).text = m
        ET.SubElement(t, q("name")).text = name
        main_root.append(t)
    main_root.append(version)
    ET.indent(main_tree, space="    ")
    main_tree.write(os.path.join(BUILD, "package.xml"), encoding="UTF-8", xml_declaration=True)

    # 5. Nothing may point at staging.
    leaks = []
    for path in glob.glob(os.path.join(BUILD, "**", "*"), recursive=True):
        if os.path.isdir(path):
            continue
        try:
            with open(path, encoding="utf-8") as fh:
                text = fh.read()
        except UnicodeDecodeError:
            continue
        if re.search(r"--staging|\.sandbox\.", text):
            leaks.append(os.path.relpath(path, BUILD))
    if leaks:
        raise SystemExit("still pointing at staging: " + ", ".join(leaks))

    counts = {t.find(q("name")).text: len(t.findall(q("members"))) for t in main_root.findall(q("types"))}
    print("build ready:", sum(counts.values()), "components")
    for name, n in counts.items():
        print(f"  {n:4d}  {name}")


if __name__ == "__main__":
    sys.exit(main())
