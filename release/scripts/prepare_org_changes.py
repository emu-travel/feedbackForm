"""Prepare the changes to production's own metadata for the feedback release.

These components belong to the org, not to this project, so they are never
copied from staging. Each is taken from the production backup and changed
only as agreed:

  Booking record pages   Add the read-only "Feedback" section (Survey Sent On,
                         Survey Reminder Sent, Feedback erhalten am) as one
                         full-width column just above System Information, and
                         remove the old survey buttons (Booking__c.SendSurvey,
                         SendSurveyInvitation) wherever they sit. Only the two
                         pages bookings actually use: the unassigned 2025 page
                         Booking_Record_Page is left alone, because production
                         refuses to save it at all (it still lists the removed
                         related list Signatur_Anfragen__r; validation 17.09.2026).
  Booking_CRED           No edit on Booking__c.SurveySent__c (read stays).
  EMU_Admin_view_all     Gets the feedback access Golf_Extra_Feedback_Admin gives
                         in staging (dashboard, feedback records, new booking
                         fields), merged without lowering anything it has.
  Booking__c.SurveySent__c  Field history on.
  Reservation__c record type Master  Allows the line status "Completed", as
                         in staging, so a booking can move to Completed.

Writes a metadata-format folder with its own package.xml:

  python release/scripts/prepare_org_changes.py backups/production-2026-09-17/metadata release/org-changes
"""

import os
import re
import shutil
import sys
import uuid

SRC, OUT = sys.argv[1], sys.argv[2]
PAGES = ["Booking_Record_Page1", "Booking_Group_Record_Page"]
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

# PERMISSION SETS ARE ALWAYS WRITTEN WHOLE. Deploying a permission set replaces
# its contents with the file: a file carrying only the changed entries removes
# every other permission. That happened in production on 17.09.2026 (17:40 to
# 17:49 Berlin) and was restored from the backup. Both files below are the
# complete backed-up permission set with only the agreed change applied.

# Booking_CRED: the backup, with Survey Sent read-only.
cred = read(os.path.join(SRC, "permissionsets", "Booking_CRED.permissionset"))
new_cred, count = re.subn(
    r"<editable>true</editable>(\s*<field>Booking__c\.SurveySent__c</field>\s*<readable>true</readable>)",
    r"<editable>false</editable>\1",
    cred,
)
if count != 1:
    raise SystemExit("Booking_CRED: Survey Sent is not editable in the backup - nothing to change, check again")
write(os.path.join(OUT, "permissionsets", "Booking_CRED.permissionset"), new_cred)
print("Booking_CRED: complete permission set, Survey Sent read-only (was editable)")

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

# The whole backed-up permission set, with the new and raised entries put in
# (replacing an entry of the same name), grouped and sorted as Salesforce writes
# them.
import xml.etree.ElementTree as ET

PS_NS = "http://soap.sforce.com/2006/04/metadata"
ET.register_namespace("", PS_NS)
ENTRY_KEYS = {
    "applicationVisibilities": "application", "classAccesses": "apexClass", "customMetadataTypeAccesses": "name",
    "customPermissions": "name", "customSettingAccesses": "name", "fieldPermissions": "field", "flowAccesses": "flow",
    "objectPermissions": "object", "pageAccesses": "apexPage", "recordTypeVisibilities": "recordType",
    "tabSettings": "tab", "userPermissions": "name",
}


def tag_of(el):
    return el.tag.split("}", 1)[1]


def entry_key(el):
    key = ENTRY_KEYS.get(tag_of(el))
    child = el.find("{%s}%s" % (PS_NS, key)) if key else None
    return (tag_of(el), child.text if child is not None else "")


full = ET.ElementTree(ET.fromstring(view_all.encode("utf-8")))
root = full.getroot()
replacements = {}
for kind, blocks in to_write.items():
    for _, block in blocks:
        el = ET.fromstring(f'<PermissionSet xmlns="{PS_NS}">{block}</PermissionSet>')[0]
        replacements[entry_key(el)] = el
children = [replacements.pop(entry_key(el), el) for el in list(root)]
children.extend(replacements.values())
for el in list(root):
    root.remove(el)
for el in sorted(children, key=lambda el: (tag_of(el), entry_key(el)[1])):
    root.append(el)
ET.indent(full, space="    ")
out_path = os.path.join(OUT, "permissionsets", "EMU_Admin_view_all.permissionset")
os.makedirs(os.path.dirname(out_path), exist_ok=True)
full.write(out_path, encoding="UTF-8", xml_declaration=True)
print(
    f"EMU_Admin_view_all: complete permission set with the feedback access | {added} added, {raised} raised,"
    f" {kept} already allowed | Survey Sent untouched"
)
before_entries = {entry_key(el) for el in ET.fromstring(view_all.encode("utf-8"))}
after_root = ET.parse(out_path).getroot()
missing = before_entries - {entry_key(el) for el in after_root}
if missing:
    raise SystemExit(f"EMU_Admin_view_all: {len(missing)} backed-up entries would be lost - not writing a partial set")
survey_sent = [el for el in after_root if entry_key(el) == ("fieldPermissions", "Booking__c.SurveySent__c")]
if not survey_sent or survey_sent[0].find("{%s}editable" % PS_NS).text != "true":
    raise SystemExit("EMU_Admin_view_all: Survey Sent must stay editable as it is in production")

# Reservation__c record type "Master": allow the line status "Completed", as
# staging does. Production's record type leaves it out, so when a booking moves
# to Completed the org's booking flow cannot set its lines to Completed and the
# whole save is refused - by hand, and when the invitation moves a trip on.
# Proven check-only in both orgs on 17.09.2026. Every other picklist on the
# record type is written back exactly as production has it.
res = read(os.path.join(SRC, "objects", "Reservation__c.object"))
rt = re.search(r"    <recordTypes>\n.*?</recordTypes>\n", res, re.S).group(0)
status = re.search(r"<picklistValues>\s*<picklist>Status__c</picklist>.*?</picklistValues>", rt, re.S)
if status is None:
    raise SystemExit("Reservation__c.Master: no Status__c values in the backup - retrieve it with its picklist fields")
block = status.group(0)
existing_values = re.findall(r"<fullName>([^<]*)</fullName>", block)
if "Completed" in existing_values:
    raise SystemExit("Reservation__c.Master: Completed is already allowed in the backup - nothing to change")
completed = (
    "            <values>\n"
    "                <fullName>Completed</fullName>\n"
    "                <default>false</default>\n"
    "            </values>\n"
)
entries = list(re.finditer(r"            <values>\s*<fullName>([^<]*)</fullName>.*?</values>\n", block, re.S))
after = [m for m in entries if m.group(1).lower() > "completed"]
at = after[0].start() if after else entries[-1].end()
new_block = block[:at] + completed + block[at:]
new_rt = rt.replace(block, new_block, 1)
write(
    os.path.join(OUT, "objects", "Reservation__c.object"),
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">\n' + new_rt + "</CustomObject>\n",
)
print(f"Reservation__c.Master: line status Completed allowed ({len(existing_values)} -> {len(existing_values) + 1} values)")

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
    "    <types>\n"
    "        <members>Reservation__c.Master</members>\n"
    "        <name>RecordType</name>\n"
    "    </types>\n"
    f"    <version>{API_VERSION}</version>\n"
    "</Package>\n",
)
print("written:", OUT)
