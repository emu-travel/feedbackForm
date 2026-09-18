# Feedback release to production

Go-live: **15.10.2026** (moved from 21.09.2026 on 18.09.2026). Production org alias `gx-prod`, API 67.0.

## What is in here

| Path                                                 | What it is                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| ---------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `package.xml`                                        | Every project component that goes to production (225), generated from `force-app` and trimmed                                                                                                                                                                                                                                                                                                                                                                          |
| `production/Gx_Feedback_Setting.Default.md-meta.xml` | The settings record with production values: survey address `https://emu-travel.my.site.com/feedback/`, Survey Start Date `2026-10-15`                                                                                                                                                                                                                                                                                                                                  |
| `org-changes/`                                       | Changes to production's own metadata, made from the production backup: Feedback section on the two booking pages in use (`Booking_Record_Page1`, `Booking_Group_Record_Page`), Survey Sent read-only in `Booking_CRED`, field history on `SurveySent__c`, `Completed` allowed on the `Reservation__c` record type `Master`, and the feedback access of `Golf_Extra_Feedback_Admin` merged into `EMU_Admin_view_all` (added only, nothing it already allows is lowered) |
| `scripts/prepare_org_changes.py`                     | Builds `org-changes/` from `backups/production-2026-09-17/metadata`                                                                                                                                                                                                                                                                                                                                                                                                    |
| `scripts/build_release.py`                           | Builds `build/` (not committed): the metadata-format folder that is validated and deployed                                                                                                                                                                                                                                                                                                                                                                             |

Left out on purpose: `Golf_Extra_Feedback_Admin` (production uses `EMU_Admin_view_all` for the dashboard instead),
`Booking__c-Booking Layout` (org-owned, unchanged), `golfextra_logo` (already in production,
byte-identical), the sharing rule and label containers (only our own rules and labels are named, so production's
`Website_Guest_Access` guest rule and other labels stay untouched).

The backup of everything this release changes in production is in `backups/production-2026-09-17/`, taken read-only
on 17.09.2026. It is the rollback for the booking pages, `Booking_CRED`, `SurveySent__c` and the site.

## Build

```bash
python release/scripts/prepare_org_changes.py backups/production-2026-09-17/metadata release/org-changes
python release/scripts/build_release.py
```

The build refuses to finish if anything still points at staging.

## Phase 4: validate in production (changes nothing)

```bash
sf project deploy validate -o gx-prod --metadata-dir release/build --test-level RunSpecifiedTests --tests GxDetractorAlertTest --tests GxFeedbackDashboardControllerTest --tests GxFeedbackDispatchTest --tests GxFeedbackFormControllerTest --tests GxFeedbackSenderTest --tests GxFeedbackServiceTest --wait 45
```

Record the validation ID. It stays valid for 10 days.

**Validated in production on 17.09.2026: 230 of 230 components, 159 of 159 tests, validation ID
`0AfMz000002N21ZKAS` (tag `feedback-v1.0.2`).** Two production findings shaped the release:

- `Booking_Record_Page` (unassigned 2025 page) cannot be saved in production at all: it lists the related list
  `Signatur_Anfragen__r`, which no longer exists. It is left out of the release and stays exactly as it is.
- The `Reservation__c` record type `Master` did not allow the line status `Completed` in production (staging does).
  The org's booking flow sets every line to the booking's status, so no booking with lines could move to Completed,
  which is exactly what the invitation does. Proven check-only in both orgs. The release adds `Completed` to that
  record type; every other picklist on it is written back exactly as production has it.

Checked against staging on 17.09.2026: 229 of 229 components and 159 of 159 tests. `Booking_Record_Page` was left out of
that check only because production's version uses `Pay__c`, which exists in production but not in staging.

## Deployed to production on 17.09.2026

- Quick deploy `0AfMz000002N2SzKAK` at 17:40 Berlin: 230 of 230 components.
- **Incident, fixed:** the release carried `Booking_CRED` and `EMU_Admin_view_all` as partial files (only the changed
  entries). Deploying a permission set replaces its contents with the file, so both lost most of their other
  permissions (Booking_CRED lost its Booking object access, which the EMU Travel Designer and EMU Buchhaltung groups
  use). Both were restored at 17:49 Berlin from `backups/production-2026-09-17`, with only the agreed changes on top
  (deploy `0AfMz000002N2ftKAC`), and compared entry by entry with the backup afterwards: nothing missing.
- `release/scripts/prepare_org_changes.py` now always writes complete permission sets and refuses to write one that
  would lose a backed-up entry.
- Guest permission set assigned to the site guest user; site published.

## Go-live day, before the quick deploy

Other work goes on in production in parallel. The release writes production's own components (the two booking pages,
`Booking_CRED`, `EMU_Admin_view_all`, `SurveySent__c`, the `Reservation__c` record type) as they were on 17.09.2026, so a
change someone made to them since would be overwritten. The release never deletes anything.

1. Retrieve the backup manifest again and compare it with `backups/production-2026-09-17/metadata`.
2. If anything differs, do not quick-deploy: take a fresh backup, rebuild `org-changes/` from it, build and validate again.
3. The quick deploy is also refused if Apex was deployed to production after the validation, or after 10 days. Then
   validate again (same command) and quick-deploy the new ID.

```bash
sf project retrieve start -o gx-prod --manifest backups/production-2026-09-17/package.xml --target-metadata-dir .go-live-check --unzip
```

Then follow Phase 5 of the go-live plan: quick deploy, guest permission set on the site guest user, publish the site,
smoke test, nightly job last. Dashboard access comes with EMU_Admin_view_all (part of the release), so there is no
admin permission set to assign.
