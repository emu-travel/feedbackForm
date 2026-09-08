# Golf Extra — Post-Trip Feedback Form (Salesforce)

Salesforce implementation of the Golf Extra GmbH post-trip guest feedback survey.
Guests receive an email after their golf trip and complete a personalised survey
built from the itinerary they actually booked.

## Repository layout

```
force-app/main/default/     Salesforce source (objects, classes, lwc, permissionsets)
config/                     Scratch org definition
manifest/package.xml        Deployment manifest
scripts/                    Anonymous Apex + SOQL helper scripts
reference-app/              React/Vite prototype — VISUAL SPEC ONLY, never deployed
```

`reference-app/` is the original AI Studio prototype. It is the source of truth for
_behaviour and design_, not for production code. It is excluded from deployment via
`.forceignore`. Its functional write-up lives in
[`reference-app/TECHNICAL_DOCUMENTATION.md`](reference-app/TECHNICAL_DOCUMENTATION.md).

## Architecture

Itinerary data is owned by an **external CMS**, not Salesforce. When a trip completes,
the CMS pushes a snapshot into Salesforce along with an invitation token. The guest-facing
form reads only that snapshot — no live callout at render time.

```
CMS (booking system of record)
      │  trip completes
      ▼
POST /services/apexrest/gx/v1/invitation      (integration user, OAuth client credentials)
      ├─ upsert Trip_Itinerary__c            on CMS_Booking_Id__c
      ├─ upsert Itinerary_Hotel__c / _Golf_Course__c / _Flight__c on CMS_Item_Id__c
      └─ insert Feedback_Invitation__c  →  { token, surveyUrl }
      │
      ▼
Email with tokenised link  →  Experience Cloud public page  →  gxSurveyContainer (LWC)
      │
      ▼
GxSurveyController.getContext(token)   reads the snapshot
GxSurveyController.submit(token, json) writes Feedback_Response__c + Feedback_Rating__c
      │
      ▼
Reports & dashboards (NPS by month, average score per hotel, detractor list)
```

### Why a snapshot rather than a live CMS callout

- The guest user never triggers an outbound callout — no latency or uptime coupling.
- Feedback records what the guest actually rated, even if the CMS itinerary changes later.
- Ratings are reportable natively in Salesforce.

## Data model

| Object                     | Purpose                                                          |
| -------------------------- | ---------------------------------------------------------------- |
| `Feedback_Invitation__c`   | Token, contact, booking ref, expiry, status, language            |
| `Trip_Itinerary__c`        | Guest + trip header, review URLs, booked-service flags           |
| `Itinerary_Hotel__c`       | One row per booked hotel — drives the dynamic hotel rating cards |
| `Itinerary_Golf_Course__c` | One row per booked course — drives the course rating cards       |
| `Itinerary_Flight__c`      | Flight legs shown in the itinerary summary                       |
| `Feedback_Response__c`     | One submission: overall, consultation, NPS, free-text answers    |
| `Feedback_Rating__c`       | One row per rated item (category, item name, score, comment)     |

Ratings are normalised into child rows rather than columns, so adding a fourth golf course
to a trip requires no schema change.

## Survey behaviour to preserve

Ported from `reference-app/src/components/SurveyView.tsx`:

- Screens skip themselves based on which services were booked (`getNextScreen`/`getPrevScreen`)
- Any rating `<= 8` reveals a follow-up comment box
- A hotel rating `< 9` expands four sub-ratings: room, service, catering, cleanliness
- A recommendation score `>= 9` reveals the Trustpilot and Google Maps review cards;
  `<= 8` shows a quiet thank-you with no public review prompt
- All ratings are on a 1–10 scale
- German-first copy, with English as a translated variant

## Development

**Prerequisites:** Node.js 20+, Salesforce CLI (`npm install --global @salesforce/cli`)

```bash
npm install                                   # dev dependencies (eslint, jest, prettier)
sf org login web --alias gx-sandbox --instance-url https://test.salesforce.com --set-default
sf org display --target-org gx-sandbox        # confirm which org you are pointed at
```

`sfdx-project.json` sets `sfdcLoginUrl` to `https://test.salesforce.com` — this project
targets sandboxes by default.

### Everyday commands

```bash
npm run test:unit          # LWC Jest tests
npm run lint               # ESLint over lwc/aura
npm run prettier:verify    # formatting check
sf project deploy start --dry-run --target-org gx-sandbox    # validate only
sf project deploy start --target-org gx-sandbox              # deploy
sf apex run test --target-org gx-sandbox --code-coverage --result-format human
sf project retrieve start --target-org gx-sandbox            # pull org changes back to source
```

## Working agreement

1. Develop against the **sandbox**, never production.
2. Metadata lives in this repo. Anything changed in the org UI gets retrieved back into source.
3. Tests are written alongside components, not afterwards — Apex tests with real assertions
   (target ~90%, not the 75% floor) and Jest tests for the conditional-reveal logic.
4. Validate with `--dry-run` before any deploy.
5. Deploy from source with the CLI. No change sets.

## Security notes

The survey is served to unauthenticated guests on the public internet:

- Record IDs are never exposed to the client; the token is the only handle.
- Tokens are cryptographically random, single-use, and expiring.
- Every score is re-validated server-side (1–10); free text is sanitised.
- The guest profile gets read access to itinerary objects and create access to feedback
  objects — nothing else.
- The inbound CMS endpoint uses a dedicated integration user, never the guest user.
