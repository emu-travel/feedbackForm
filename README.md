# Golf Extra - Post-Trip Feedback (Salesforce)

The golf.extra / EMU exclusive travel post-trip feedback survey and the team's Feedback
Dashboard. After a golf trip the guest receives an email with a personal link, rates exactly
what they booked (flights, transfers, rental car, each hotel, each golf course) and the team
reads the answers on the dashboard.

## Repository layout

```
force-app/main/default/     Salesforce source - everything below is deployed
scripts/apex/               Anonymous Apex for dispatch and go-live
manifest/package.xml        Deployment manifest
config/                     Scratch org definition
```

## How it works

```
GxFeedbackScheduler (nightly, 07:00)
   │  invites trips marked Traveled that ended 36 h ago; one reminder 10 days later, never after an answer
   ▼
Gx_Feedback_Invitation / Gx_Feedback_Reminder   (Lightning email templates, German)
   │  personal link: https://…/feedback/?b={BookingNumber__c}&k={Form_Secret__c}
   ▼
LWR site "Golf Extra Feedback"  →  gxFeedbackForm (LWC)
   │  GxFeedbackFormController  (the only Apex the guest may call)
   │  GxFeedbackService         (link check, itinerary, validation, save)
   ▼
Feedback_Response__c  +  Feedback_Rating__c
   │                                   │
   │  recommendation 6 or below        ▼
   ▼                            Feedback Dashboard (gxFeedbackDashboard, GxFeedbackDashboardController)
Gx_Detractor_Alert__e → GxDetractorAlert (email to the travel designer)
```

### The survey

- Screens follow the booking: overall and consultation, then flights / transfers / rental car,
  hotels, golf courses, conclusion. A screen the trip did not have is skipped.
- Only delivered travel is rated. The itinerary comes from `Reservation__c`; the category is
  **`AccountType__c`** (`Type__c` is empty on every row), the name is
  `Travel_Location__r.Name`. Repeat rows for the same venue become one card.
- A rating of 8 or below opens an optional comment. A hotel below 9 opens four detail ratings
  (room, service, catering, cleanliness).
- A recommendation of 9 or 10 shows the Trustpilot and Google review buttons on the thank-you page.
- Every guest-facing text is a Custom Label `Gx_Survey_*` (category "Golf Extra Feedback
  Survey"), so the wording can change in Setup. The site serves a compiled copy: **publish the
  site after editing a label**, and retrieve the labels into this repo before the next deploy.
- The survey is German. The hotel's country is shown with the German name from
  `Booking__c.DestinationCountry__c`.
- A link stops working 14 days after the last invitation or reminder.
- **What the guest rates is saved with the first invitation** (`Booking__c.Survey_Snapshot__c`)
  and read from there. Later changes to the booking (lines canceled, hotels swapped, stays
  added, automation touching line statuses) never reach a survey already sent, and there is no
  refresh: the booking has to be right by the invitation. A rating whose line was deleted since is
  kept without the link. Only a booking invited before the list was kept is read live, keeping to
  lines that start on or before the saved trip end.
- Answers are kept on the guest's device as they go (browser storage, nothing is sent before
  submitting). Reopening the link on the same device resumes on the same step. The draft is
  deleted on submit, when the link is answered or expired, and is never restored after 14 days.

### Sending

- `GxFeedbackScheduler` → `GxFeedbackDispatch` → `GxFeedbackSender`. Rules and addresses live
  in the custom metadata record `Gx_Feedback_Setting.Default` (start date, delays, link
  validity, sender `anfrage@golf-extra.com`, review links, alert switch and copy address
  `ali.haider@emu-travel.com`, which also receives the nightly run's problem notice).
- Only trips that ended on or after `Survey_Start_Date__c` and within `Max_Trip_Age_Days__c`
  are invited, so switching the job on never mails old guests.
- A guest who has answered is never reminded (checked in the query and again before sending).
- **One refused booking does not stop the night.** The due bookings are saved together; when the
  org refuses some of them (a rule, or a fault in a record-triggered flow, which fails every booking
  saved alongside it), the refused ones are split and saved again until only the booking at fault is
  left, within the run's governor limits. That booking is left untouched and tried again at the next
  run; everyone else is emailed as normal.
- **Someone is told.** When a guest due that morning could not be asked, `GxFeedbackRunNotice` emails
  the alert copy address with each booking and the reason, marked `[Sandbox]` in a sandbox. A
  refused booking repeats in the notice every morning until it is fixed. An email that failed after
  the booking was saved is not retried by itself; the notice says to resend it with
  `scripts/apex/send-feedback-invitation.apex`.
- **Booking status:** the team marks a trip **Traveled**; sending the invitation moves it to
  **Completed** (a trip someone already marked Completed stays there); the guest's answer moves it
  to **Feedback**. Only Traveled and Completed trips are invited, so a trip still at Paid or
  Invoiced waits. The validation rule `Gx_Feedback_Only_After_Answer` refuses Feedback by hand
  while no answer exists.
- The flow `Gx_Send_Feedback_Survey` and the Booking quick action of the same name are kept
  deliberately **off** the page layout: sending is automatic. They are the recovery path when a
  guest says the email never arrived (`scripts/apex/send-feedback-invitation.apex` does the same).

### Detractor alerts

A recommendation of 6 or below publishes `Gx_Detractor_Alert__e` after the answer is saved;
the trigger emails the trip's travel designer with the alert copy address in copy. In a
sandbox the designer is never emailed - the alert goes to the copy address only, marked
`[Sandbox]`.

### Feedback Dashboard

Lightning tab `Gx_Feedback_Dashboard`, for users with the permission set
**Golf Extra Feedback - Admin** (in production the same access comes with the existing permission set
**EMU Admin view all**, which holds the org's admins; the Golf Extra set is not deployed there):

- Headline numbers: responses, response rate, NPS, overall and consultation averages, open follow-ups.
- Dates are the trip as it was when the guest was invited (`Survey_Trip_End__c`), so a later change
  to the booking does not move its feedback out of its trip month.
- NPS is % promoters (9-10) minus % detractors (0-6) over everyone who answered, to one
  decimal, and can be negative. 7-8 are **Neutrals**.
- Responses: search by guest, email, booking, FB number, region or country; groups; newest or
  lowest first; paging; **Export to Excel** (CSV with BOM, `application/octet-stream` because
  Lightning Web Security refuses a `text/csv` blob).
- NPS by trip month, travel designers, venue and partner scores with search and every rating
  per venue, hotel detail, unhappy guests to follow up, next destinations.
- **Full response** shows one answer as the guest gave it, with the survey's icons.
- Volume guards: the dashboard refuses a selection above 20,000 responses (venue scores above
  45,000 ratings) and asks for narrower filters instead of failing; lists are capped and paged.

## Data model

| Object / field                                                              | Purpose                                                                                                                                                     |
| --------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Feedback_Response__c`                                                      | One answer per booking: overall, consultation, recommendation (`NPS_Category__c`), free text, follow-up status / note / by / on                             |
| `Feedback_Rating__c`                                                        | One row per rated item or hotel detail: category, item name, score, comment, lookup to the `Reservation__c`                                                 |
| `Booking__c.Survey_Link__c`, `Survey_Sent_On__c`, `Survey_Reminder_Sent__c` | The personal link and the sending bookkeeping                                                                                                               |
| `Booking__c.Survey_Trip_Summary__c`, `Survey_Logo_URL__c`                   | Merge fields for the emails                                                                                                                                 |
| `Booking__c.Feedback_Received_On__c` ("Feedback erhalten am")               | Roll-up of the latest `Submitted_On__c`: empty while the guest has not answered, set the moment they submit. The same answer moves the status to "Feedback" |
| `Booking__c.Survey_Trip_Start__c`, `Survey_Trip_End__c`                     | The trip dates as they were at the first invitation. Reminders and later edits to the booking leave them alone; the dashboard filters and groups by them    |
| `Booking__c.Survey_Snapshot__c`                                             | What the guest rates, saved as JSON with the first invitation and read by the survey instead of the booking's current lines. Never rebuilt                  |
| `Gx_Feedback_Setting__mdt`                                                  | All settings (see Sending)                                                                                                                                  |
| `Gx_Detractor_Alert__e`                                                     | Platform event behind the alert                                                                                                                             |

## Security

The survey is public, so:

- The only handle is `BookingNumber__c` + `Form_Secret__c`; record IDs never reach the browser.
- The guest permission set **Golf Extra Feedback - Guest** grants the form controller only.
  Guest sharing rules expose invited bookings (`SurveySent__c = true`) and supplier accounts,
  never customer accounts.
- Scores are re-checked on the server (1-10), free text is stripped of markup and capped, and a
  booking accepts one response only.
- The site sends `noindex, nofollow`.

## Development

**Prerequisites:** Node.js 20+, Salesforce CLI (`npm install --global @salesforce/cli`)

```bash
npm install
sf org login web --alias gx-sandbox --instance-url https://test.salesforce.com --set-default
```

```bash
npm run test:unit                                     # LWC Jest tests
npm run lint                                          # ESLint
sf project deploy start --dry-run -o gx-sandbox       # validate
sf project deploy start -o gx-sandbox                 # deploy
sf apex run test -o gx-sandbox --code-coverage --result-format human
sf community publish -o gx-sandbox --name "Golf Extra Feedback"   # after LWC or label changes
```

## Working agreement

1. Develop and test in the staging sandbox; production only after sign-off.
2. Metadata lives in this repo. Anything changed in Setup is retrieved back before the next deploy.
3. Apex tests with real assertions, Jest tests for the survey and dashboard logic.
4. Deploy from source with the CLI, no change sets.

## Go-live

1. Build and deploy the release in `release/` (see `release/README.md`: production settings, production's own
   booking pages and permission changes, check-only validation first); publish the site.
2. Set `Gx_Feedback_Setting.Default`: `Survey_Base_URL__c` (production site), `Survey_Start_Date__c`
   (go-live date), `Alert_Copy_Email__c`.
3. Verify the org-wide address `anfrage@golf-extra.com` and email deliverability.
4. Dashboard access: the release adds it to **EMU Admin view all**, so its holders have it without an assignment.
5. Booking record pages: add the read-only **Feedback** section to the Details tab as one full-width
   column (Survey Sent On, Survey Reminder Sent, Feedback erhalten am), so no label wraps. There is no
   Feedback Responses list on the booking: the answers are read on the dashboard. These Lightning pages
   belong to the org, not to this repo: retrieve them from production, add the section, deploy.
   Mind the duplicate label: the sandbox has two record pages both labelled "Booking Record Page"
   (`Booking_Record_Page`, from 2025, assigned to nothing, and `Booking_Record_Page1`, the one bookings
   actually render). Check Activation in the Lightning App Builder to see which page is assigned before
   editing, and remove the old **Send Survey** button (`Booking__c.SendSurvey`, from the earlier
   Salesforce Surveys attempt) wherever it sits on an assigned page: it sends the old survey and ticks
   Survey Sent, so the nightly job would skip that booking. Remove the standard **Send Survey
   Invitation** button as well, so no booking page offers a way to send the old Salesforce survey; in the
   sandbox both buttons are gone from both pages. Also remove edit on `SurveySent__c` from Booking CRED
   and turn on field history for SurveySent__c, as done in the sandbox.
6. Last step: `scripts/apex/schedule-feedback-dispatch.apex`.
