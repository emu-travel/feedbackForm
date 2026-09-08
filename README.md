# Golf Extra — Post-Trip Feedback Form (Salesforce)

Salesforce implementation of the golf.extra / EMU exclusive travel post-trip guest feedback
survey. Guests receive an email after their golf trip and complete a personalised survey built
from the itinerary they actually booked.

## Repository layout

```
force-app/main/default/     Salesforce source (objects, classes, lwc, permissionsets)
config/                     Scratch org definition
manifest/package.xml        Deployment manifest
scripts/                    Anonymous Apex + SOQL helper scripts
reference-app/              React/Vite prototype — VISUAL SPEC ONLY, never deployed
```

`reference-app/` is the original AI Studio prototype. It is the source of truth for
_behaviour and design_, not for production code, and is excluded from deployment via
`.forceignore`. Its functional write-up is in
[`reference-app/TECHNICAL_DOCUMENTATION.md`](reference-app/TECHNICAL_DOCUMENTATION.md).

## Architecture

All data already lives in Salesforce. There is no external system and no integration layer.
The survey reads the itinerary directly from the existing booking model and writes feedback
into two new objects.

```
Booking__c  (trip header — already exists)
   │  SendSurvey__c / SurveySent__c / Form_Secret__c  ← already exist
   │
   ├── Reservation__c (itinerary line items — already exist)
   │      AccountType__c: Hotel | Golfclub | Airline | TransferCompany | CarRentalCompany | …
   │      Travel_Location__r.Name → the hotel / golf club / supplier
   │
   ▼
Email with tokenised link  →  Experience Cloud public page
   https://…/feedback?b={BookingNumber__c}&k={Form_Secret__c}
   │
   ▼
gxFeedbackForm (LWC)
   │
   ▼
GxFeedbackFormController   thin, `with sharing`, the only Apex the guest may call
GxFeedbackService          `without sharing`, token check + rate limit + all logic
   │
   ▼
Feedback_Response__c  +  Feedback_Rating__c        ← the only new objects
   │
   ▼
Reports & dashboards (NPS by month, average score per hotel / course, detractor list)
```

### Reusing what the org already has

This org already solved guest access for the **Reiseanmeldung** booking-confirmation form.
We follow that pattern rather than inventing a parallel one:

| Existing                                                 | Reused for                                      |
| -------------------------------------------------------- | ----------------------------------------------- |
| `Booking__c.Form_Secret__c`                              | The invitation token — no new invitation object |
| `ReiseanmeldungFormController` / `ReiseanmeldungService` | Shape of our controller/service pair            |
| LWC `reiseanmeldungForm` (reads `?b=` and `?k=`)         | URL parameter handling                          |
| `Booking__c.SendSurvey__c` / `SurveySent__c`             | Dispatch flags, already flow-driven             |
| Experience Cloud public site pattern                     | Where the form is hosted                        |

### Reading the itinerary — important

`Reservation__c.Type__c` looks like the right discriminator but is **null on every row**.
The populated field is **`AccountType__c`**:

| `AccountType__c`                       | Survey section                                      |
| -------------------------------------- | --------------------------------------------------- |
| `Hotel`                                | Per-hotel rating card, sub-ratings when score `< 9` |
| `Golfclub`                             | Per-course rating card                              |
| `Airline`                              | Flight rating                                       |
| `TransferCompany`                      | Transfer / chauffeur rating                         |
| `CarRentalCompany`                     | Rental car rating                                   |
| `Insurance`, `DMC`, `General Services` | Not rated                                           |

Names come from `Travel_Location__r.Name`; `Service__r.Name` holds the service description.
Only delivered travel is rated — filter `Status__c` to `Booked` / `Invoiced` / `Paid` /
`Completed`, excluding `Calculation` / `Offered` / `Accepted` / `Rejected` / `Canceled`.

Repeat rows for the same venue collapse into one rating card (a real booking carries the same
hotel on four rows, one per room); distinct venues never collapse, so a guest who booked three
hotels and two courses gets three hotel cards and two course cards.

The golf card deliberately omits a hole count and highlight badge: no such field exists on
`Account`, `Service__c` or `Reservation__c`, and adding one would be a data-maintenance
commitment rather than a code change. Courses show name, service description and `TeeTime__c`.

## New data model

| Object                 | Purpose                                                           |
| ---------------------- | ----------------------------------------------------------------- |
| `Feedback_Response__c` | One submission per booking: overall, consultation, NPS, free text |
| `Feedback_Rating__c`   | One row per rated item — category, item name, score, comment      |

Ratings are normalised into child rows rather than columns, so a trip with four golf courses
instead of three needs no schema change. Each rating keeps a lookup to the `Reservation__c` it
came from, so "average score for Real Club Valderrama" is a report, not code.

## Why not Salesforce Surveys

Feedback Management is already in this org and was tried: seven `Survey` records dating to
Sept 2025, including an active `golf.extra Feedback`. It never launched —
`SurveyInvitation` and `SurveyResponse` both hold zero rows. The existing survey is a flat
25-question single page with no conditional logic and no per-hotel or per-course
personalisation, which is precisely what the prototype was built to replace.

## Survey behaviour to preserve

Ported from `reference-app/src/components/SurveyView.tsx`:

- Screens skip themselves based on which services were booked
- Any rating `<= 8` reveals a follow-up comment box
- A hotel rating `< 9` expands four sub-ratings: room, service, catering, cleanliness
- A recommendation score `>= 9` reveals the Trustpilot and Google Maps review cards;
  `<= 8` shows a quiet thank-you with no public review prompt
- All ratings are on a 1–10 scale
- German-first copy, with English as a translated variant

## Development

**Prerequisites:** Node.js 20+, Salesforce CLI (`npm install --global @salesforce/cli`)

```bash
npm install
sf org login web --alias gx-sandbox --instance-url https://test.salesforce.com --set-default
sf org display --target-org gx-sandbox
```

`sfdx-project.json` sets `sfdcLoginUrl` to `https://test.salesforce.com`; this project targets
sandboxes by default. Production deployment is a deliberate, separate step.

### Everyday commands

```bash
npm run test:unit          # LWC Jest tests
npm run lint               # ESLint over lwc/aura
npm run prettier:verify    # formatting check
sf project deploy start --dry-run --target-org gx-sandbox    # validate only
sf project deploy start --target-org gx-sandbox              # deploy
sf apex run test --target-org gx-sandbox --code-coverage --result-format human
sf project retrieve start --target-org gx-sandbox            # pull org changes into source
```

## Working agreement

1. Develop and test in the **staging sandbox**, then promote to production.
2. Metadata lives in this repo. Anything changed in the org UI is retrieved back into source.
3. Tests are written alongside components — Apex tests with real assertions (target ~90%,
   not the 75% floor) and Jest tests for the conditional-reveal logic.
4. Validate with `--dry-run` before any deploy.
5. Deploy from source with the CLI. No change sets.
6. Never modify the existing Reiseanmeldung or booking metadata; this project only adds.

## Security notes

The survey is served to unauthenticated guests on the public internet:

- Record IDs are never exposed to the client; `BookingNumber__c` + `Form_Secret__c` is the
  only handle, exactly as the Reiseanmeldung form does it.
- The guest profile gets access to `GxFeedbackFormController` only — no object permissions of
  its own. All logic runs in `GxFeedbackService` (`without sharing`).
- Every score is re-validated server-side (1–10); free text is length-capped and sanitised.
- Submissions are rate-limited per booking, following the existing form's 10/hour precedent.
- One response per booking; re-submission is rejected.
