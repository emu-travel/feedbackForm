# Feedback release to production

Go-live: **21.09.2026**. Production org alias `gx-prod`, API 67.0.

## What is in here

| Path                                                 | What it is                                                                                                                                                                                                                                              |
| ---------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `package.xml`                                        | Every project component that goes to production (225), generated from `force-app` and trimmed                                                                                                                                                           |
| `production/Gx_Feedback_Setting.Default.md-meta.xml` | The settings record with production values: survey address `https://emu-travel.my.site.com/feedback/`, Survey Start Date `2026-09-21`                                                                                                                   |
| `org-changes/`                                       | Changes to production's own metadata, made from the production backup: Feedback section on the three booking pages (and the old survey buttons off the unassigned 2025 page), Survey Sent read-only in `Booking_CRED`, field history on `SurveySent__c` |
| `scripts/prepare_org_changes.py`                     | Builds `org-changes/` from `backups/production-2026-09-17/metadata`                                                                                                                                                                                     |
| `scripts/build_release.py`                           | Builds `build/` (not committed): the metadata-format folder that is validated and deployed                                                                                                                                                              |

Left out on purpose: `Booking__c-Booking Layout` (org-owned, unchanged), `golfextra_logo` (already in production,
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

Checked against staging on 17.09.2026: 229 of 229 components and 159 of 159 tests. `Booking_Record_Page` was left out of
that check only because production's version uses `Pay__c`, which exists in production but not in staging.

## Go-live day, before the quick deploy

Production's booking pages may have been edited since the backup. Retrieve them again and compare; if anything
changed, rebuild `org-changes/` from a fresh backup and validate again instead of deploying.

```bash
sf project retrieve start -o gx-prod --manifest backups/production-2026-09-17/package.xml --target-metadata-dir .go-live-check --unzip
```

Then follow Phase 5 of the go-live plan: quick deploy, guest permission set on the site guest user, publish the site,
admin permission set for Ergül Altinova, Kaan Vincent Altinova and Ali Haider, smoke test, nightly job last.
