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
    "        <name>PermissionSet</name>\n"
    "    </types>\n"
    f"    <version>{API_VERSION}</version>\n"
    "</Package>\n",
)
print("written:", OUT)
