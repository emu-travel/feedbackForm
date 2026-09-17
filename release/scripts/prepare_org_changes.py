"""Prepare the changes to production's own metadata for the feedback release.

These components belong to the org, not to this project, so they are never
copied from staging. Each is taken from the production backup and changed
only as agreed:

  Booking record pages   Add the read-only "Feedback" section (Survey Sent On,
                         Survey Reminder Sent, Feedback erhalten am) as one
                         full-width column just above System Information, and
                         remove the old survey buttons (Booking__c.SendSurvey,
                         SendSurveyInvitation) wherever they sit.
  Booking_CRED           No edit on Booking__c.SurveySent__c (read stays).
  EMU_Admin_view_all     Gets the feedback access Golf_Extra_Feedback_Admin gives
                         in staging (dashboard, feedback records, new booking
                         fields), merged without lowering anything it has.
  Booking__c.SurveySent__c  Field history on.

Writes a metadata-format folder with its own package.xml:

  python release/scripts/prepare_org_changes.py backups/production-2026-09-17/metadata release/org-changes
"""

import os
import re
import shutil
import sys
import uuid

SRC, OUT = sys.argv[1], sys.argv[2]
PAGES = ["Booking_Record_Page", "Booking_Record_Page1", "Booking_Group_Record_Page"]
FIELDS = ["Survey_Sent_On__c", "Survey_Reminder_Sent__c", "Feedback_Received_On__c"]
OLD_BUTTONS = ["Booking__c.SendSurvey", "SendSurveyInvitation"]
MARK = "gxFeedback"
API_VERSION = "67.0"


def read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)


def field_items():
    items = []
    for f in FIELDS:
        items.append(
            "        <itemInstances>\n"
            "            <fieldInstance>\n"
            "                <fieldInstanceProperties>\n"
            "                    <name>uiBehavior</name>\n"
            "                    <value>readonly</value>\n"
            "                </fieldInstanceProperties>\n"
            f"                <fieldItem>Record.{f}</fieldItem>\n"
            f"                <identifier>Record{f.replace('__c', '_c')}Field_{MARK}</identifier>\n"
            "            </fieldInstance>\n"
            "        </itemInstances>"
        )
    return "\n".join(items)


def region(name, items):
    return (
        "    <flexiPageRegions>\n"
        f"{items}\n"
        f"        <name>{name}</name>\n"
        "        <type>Facet</type>\n"
        "    </flexiPageRegions>"
    )


def patch_page(page, text):
    if MARK in text:
        raise SystemExit(f"{page}: already has the Feedback section - not adding it twice")

    fields_facet = f"Facet-{uuid.uuid4()}"
    columns_facet = f"Facet-{uuid.uuid4()}"
    column_items = (
        "        <itemInstances>\n"
        "            <componentInstance>\n"
        "                <componentInstanceProperties>\n"
        "                    <name>body</name>\n"
        f"                    <value>{fields_facet}</value>\n"
        "                </componentInstanceProperties>\n"
        "                <componentName>flexipage:column</componentName>\n"
        f"                <identifier>flexipage_column_{MARK}1</identifier>\n"
        "            </componentInstance>\n"
        "        </itemInstances>"
    )
    section_item = (
        "<itemInstances>\n"
        "            <componentInstance>\n"
        "                <componentInstanceProperties>\n"
        "                    <name>columns</name>\n"
        f"                    <value>{columns_facet}</value>\n"
        "                </componentInstanceProperties>\n"
        "                <componentInstanceProperties>\n"
        "                    <name>horizontalAlignment</name>\n"
        "                    <value>false</value>\n"
        "                </componentInstanceProperties>\n"
        "                <componentInstanceProperties>\n"
        "                    <name>label</name>\n"
        "                    <value>Feedback</value>\n"
        "                </componentInstanceProperties>\n"
        "                <componentName>flexipage:fieldSection</componentName>\n"
        f"                <identifier>flexipage_fieldSection_{MARK}</identifier>\n"
        "            </componentInstance>\n"
        "        </itemInstances>\n        "
    )

    detail = re.search(
        r"<flexiPageRegions>(?:(?!</flexiPageRegions>).)*?<name>detailTabContent</name>\s*"
        r"<type>Facet</type>\s*</flexiPageRegions>",
        text,
        re.S,
    )
    if not detail:
        raise SystemExit(f"{page}: no detailTabContent region - page layout is not what was checked")
    block = detail.group(0)
    sys_info = re.search(
        r"<itemInstances>(?:(?!<itemInstances>).)*?@@@SFDCSystem_InformationSFDC@@@.*?</itemInstances>",
        block,
        re.S,
    )
    if not sys_info:
        raise SystemExit(f"{page}: no System Information section to place the Feedback section above")
    new_block = block[: sys_info.start()] + section_item + block[sys_info.start():]
    new_regions = "\n".join([region(fields_facet, field_items()), region(columns_facet, column_items)])
    patched = text[: detail.start()] + new_regions + "\n    " + new_block + text[detail.end():]

    removed = []
    for button in OLD_BUTTONS:
        pattern = re.compile(
            r"\s*<valueListItems>\s*<value>" + re.escape(button) + r"</value>\s*</valueListItems>", re.S
        )
        patched, n = pattern.subn("", patched)
        if n:
            removed.append(f"{button} x{n}")
    return patched, removed


shutil.rmtree(OUT, ignore_errors=True)

for page in PAGES:
    src = os.path.join(SRC, "flexipages", f"{page}.flexipage")
    original = read(src)
    patched, removed = patch_page(page, original)
    write(os.path.join(OUT, "flexipages", f"{page}.flexipage"), patched)
    print(
        f"{page}: Feedback section added above System Information"
        f" | old survey buttons removed: {', '.join(removed) if removed else 'none on this page'}"
        f" | {len(original)} -> {len(patched)} bytes"
    )

# Booking_CRED: only the one field permission is deployed, so nothing else on
# the permission set can change.
cred = read(os.path.join(SRC, "permissionsets", "Booking_CRED.permissionset"))
label = re.search(r"<label>([^<]*)</label>", cred).group(1)
if not re.search(
    r"<editable>true</editable>\s*<field>Booking__c\.SurveySent__c</field>\s*<readable>true</readable>", cred
):
    raise SystemExit("Booking_CRED: Survey Sent is not editable in the backup - nothing to change, check again")
write(
    os.path.join(OUT, "permissionsets", "Booking_CRED.permissionset"),
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<PermissionSet xmlns="http://soap.sforce.com/2006/04/metadata">\n'
    "    <fieldPermissions>\n"
    "        <editable>false</editable>\n"
    "        <field>Booking__c.SurveySent__c</field>\n"
    "        <readable>true</readable>\n"
    "    </fieldPermissions>\n"
    f"    <label>{label}</label>\n"
    "</PermissionSet>\n",
)
print("Booking_CRED: Survey Sent read-only (was editable)")

# SurveySent__c: the production field definition, with history turned on.
obj = read(os.path.join(SRC, "objects", "Booking__c.object"))
if "<trackHistory>false</trackHistory>" not in obj:
    raise SystemExit("Booking__c.SurveySent__c: history is not off in the backup - check again")
write(
    os.path.join(OUT, "objects", "Booking__c.object"),
    obj.replace("<trackHistory>false</trackHistory>", "<trackHistory>true</trackHistory>", 1),
)
print("Booking__c.SurveySent__c: field history on")

# EMU_Admin_view_all: the people who administer the feedback in production
# (decided 17.09.2026), so it gets what Golf_Extra_Feedback_Admin grants in
# staging - dashboard, feedback records, the new booking fields - instead of
# that permission set being deployed. Merged, never lowered: anything the
# permission set already allows stays as it is, and only what it lacks is
# written, so nothing else about it can change.
PERM_KEYS = {
    "classAccesses": ("apexClass", ["enabled"]),
    "fieldPermissions": ("field", ["editable", "readable"]),
    "flowAccesses": ("flow", ["enabled"]),
    "objectPermissions": (
        "object",
        ["allowCreate", "allowDelete", "allowEdit", "allowRead", "modifyAllFields", "modifyAllRecords", "viewAllFields", "viewAllRecords"],
    ),
    "tabSettings": ("tab", ["visibility"]),
}
# Metadata API order of the elements that can appear here.
PERM_ORDER = ["classAccesses", "fieldPermissions", "flowAccesses", "hasActivationRequired", "label", "objectPermissions", "tabSettings"]
TAB_RANK = {"None": 0, "Hidden": 0, "Available": 1, "DefaultOff": 1, "Visible": 2, "DefaultOn": 2}


def perm_entries(text):
    entries = {}
    for kind, (key, flags) in PERM_KEYS.items():
        for block in re.findall(rf"<{kind}>(.*?)</{kind}>", text, re.S):
            name = re.search(rf"<{key}>([^<]*)</{key}>", block).group(1)
            values = {}
            for flag in flags:
                m = re.search(rf"<{flag}>([^<]*)</{flag}>", block)
                if m:
                    values[flag] = m.group(1)
            entries[(kind, name)] = values
    return entries


def stronger(flag, ours, theirs):
    if flag == "visibility":
        return ours if TAB_RANK.get(ours, 0) > TAB_RANK.get(theirs, 0) else theirs
    return "true" if "true" in (ours, theirs) else "false"


view_all = read(os.path.join(SRC, "permissionsets", "EMU_Admin_view_all.permissionset"))
repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ours = read(
    os.path.join(repo_root, "force-app", "main", "default", "permissionsets", "Golf_Extra_Feedback_Admin.permissionset-meta.xml")
)
existing = perm_entries(view_all)
to_write = {kind: [] for kind in PERM_KEYS}
added = kept = raised = 0
for (kind, name), values in perm_entries(ours).items():
    key, flags = PERM_KEYS[kind]
    current = existing.get((kind, name))
    if current is None:
        merged = values
        added += 1
    else:
        merged = {f: stronger(f, values.get(f, "false"), current.get(f, "false")) for f in flags if f in values or f in current}
        if merged == {f: current.get(f) for f in merged}:
            kept += 1
            if kind != "objectPermissions":
                continue
            # A granted object must travel with the objects it depends on
            # (Feedback_Response__c needs Booking__c), so production's own
            # object access is written back exactly as it is.
        else:
            raised += 1
    lines = [f"        <{key}>{name}</{key}>"] + [f"        <{f}>{merged[f]}</{f}>" for f in sorted(merged)]
    to_write[kind].append((name, f"    <{kind}>\n" + "\n".join(sorted(lines)) + f"\n    </{kind}>"))

label = re.search(r"<label>([^<]*)</label>", view_all).group(1)
activation = re.search(r"<hasActivationRequired>([^<]*)</hasActivationRequired>", view_all)
parts = []
for element in PERM_ORDER:
    if element == "hasActivationRequired" and activation:
        parts.append(f"    <hasActivationRequired>{activation.group(1)}</hasActivationRequired>")
    elif element == "label":
        parts.append(f"    <label>{label}</label>")
    elif element in to_write:
        parts.extend(block for _, block in sorted(to_write[element]))
write(
    os.path.join(OUT, "permissionsets", "EMU_Admin_view_all.permissionset"),
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<PermissionSet xmlns="http://soap.sforce.com/2006/04/metadata">\n' + "\n".join(parts) + "\n</PermissionSet>\n",
)
print(
    f"EMU_Admin_view_all: feedback access merged in | {added} added, {raised} raised,"
    f" {kept} already allowed (left alone) | Survey Sent untouched"
)
if "SurveySent__c" in read(os.path.join(OUT, "permissionsets", "EMU_Admin_view_all.permissionset")):
    raise SystemExit("EMU_Admin_view_all: Survey Sent must stay as it is in production")

write(
    os.path.join(OUT, "package.xml"),
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<Package xmlns="http://soap.sforce.com/2006/04/metadata">\n'
    "    <types>\n"
    "        <members>Booking__c.SurveySent__c</members>\n"
    "        <name>CustomField</name>\n"
    "    </types>\n"
    "    <types>\n"
    + "".join(f"        <members>{p}</members>\n" for p in PAGES)
    + "        <name>FlexiPage</name>\n"
    "    </types>\n"
    "    <types>\n"
    "        <members>Booking_CRED</members>\n"
    "        <members>EMU_Admin_view_all</members>\n"
    "        <name>PermissionSet</name>\n"
    "    </types>\n"
    f"    <version>{API_VERSION}</version>\n"
    "</Package>\n",
)
print("written:", OUT)
