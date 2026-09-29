# Per-traveller feedback invitations (incl. group and PRO trips)

Every traveller gets their own survey link, built from their own itinerary. Decided
with Ali on 28.09.2026. Built and tested in the staging sandbox; production release
only after the 15.10.2026 go-live, on Ali's explicit go.

## Decisions

| Question                   | Decision                                                                                                                                                                                                                                                                                 |
| -------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Who gets a link            | Every traveller with an email address. The main contact gets one when not already a traveller. Travellers without an email are skipped.                                                                                                                                                  |
| Itinerary per person       | Captured at the **individual level**: a participant's survey uses their own participant booking's lines. No merging, because the package lines are already copied down to each participant. Fallback: a participant booking with no rateable line at all uses the group booking's lines. |
| Group organiser / PRO      | Gets one survey for the group booking, and only one: never a second if they also travel.                                                                                                                                                                                                 |
| What triggers a group trip | The **group booking's** status (Traveled or Completed). Participants are then invited, each after their own end date plus the waiting period.                                                                                                                                            |
| Booking status on answer   | The first answer moves that booking to Feedback, as today.                                                                                                                                                                                                                               |
| Scope                      | All travel types.                                                                                                                                                                                                                                                                        |
| Reminders                  | Per person, one each, only while unanswered.                                                                                                                                                                                                                                             |

## The data model (verified 28.09.2026, production and sandbox)

- A group trip is **several Booking__c records**: the parent (record type PRO) and one
  participant booking per party (record type Booking), linked by `TravelGroup__c`.
- **BookingNumber__c is not unique**: parent and participants share it (P000378ES
  exists 7 times in production).
- The parent holds the package lines; **each participant booking carries its own full
  copy** (verified on P000378ES: flight, transfer, 2 hotels on every participant), plus
  any customisation for that guest.
- Each participant booking has its own main contact, own dates and own status. Parent
  and participants can differ (parent "LT booked", participants "Accepted").
- Production: 74 bookings = 7 group parents (all PRO) + 19 participants + 48 plain.
  Travellers: 24 on participant bookings, about 87 elsewhere. Sandbox: 5 parents,
  10 participants.
- Status paths differ per record type: the PRO path has no "Traveled"; it goes
  ... Paid -> Completed -> Feedback. The code accepts Traveled **or** Completed, so PRO
  works through Completed.

## Target behaviour

1. **Recipients per booking**: travellers with an email, plus the booking's main
   contact when not already among them. Duplicates removed by contact id, then email.
2. **Group trips**: participants are invited from their own participant booking. The
   group parent invites only its own main contact (the pro or organiser), and only if
   that person was not already invited as a participant or traveller.
3. **Itinerary**: the snapshot is taken from the booking the person was invited from,
   with the group fallback described above.
4. **Link**: `?b=<booking number>&k=<secret>` stays, but resolution is by **secret
   only**, because the number is not unique.
5. **Answering**: refused only when that person has already answered.
6. **Status**: first answer moves that booking to Feedback.
7. **Reminders**: per person, one each.

## New fields on `Traveler__c`

| Field                     | Type                             | Purpose                |
| ------------------------- | -------------------------------- | ---------------------- |
| `Survey_Secret__c`        | Text(64), unique, case sensitive | the person's own link  |
| `Survey_Sent_On__c`       | Date/Time                        | when they were invited |
| `Survey_Reminder_Sent__c` | Checkbox                         | one reminder ever      |
| `Survey_Answered_On__c`   | Date/Time                        | when they answered     |

The booking keeps `Form_Secret__c` (the main contact's link), `SurveySent__c` and
`Survey_Sent_On__c` (first invitation for that booking).

## Class changes

1. **GxFeedbackScheduler** - also select participant bookings whose group parent is
   Traveled or Completed, not only bookings that qualify themselves.
2. **GxFeedbackDispatch** - build the recipient list per booking; mint a secret per
   person; snapshot per booking; per-person guards (already invited, already answered);
   new refusal reason "no recipient with an email address".
3. **GxFeedbackSender** - one email per recipient; reminders per recipient; the run
   notice names anyone who could not be reached.
4. **GxFeedbackService** - resolve by secret; per-person "already answered"; response
   carries the person; stamp `Survey_Answered_On__c`.
5. **GxFeedbackDashboardController** - response rate per person, with the per-booking
   figure kept alongside for comparison.
6. **Templates** - greet the traveller by name.

## Build order (sandbox)

1. Traveler fields.
2. Dispatch recipient list and per-person secrets, with tests: no travellers, one,
   several, missing emails, main-contact overlap, group parent plus participants.
3. Sender per recipient, incl. reminders.
4. Service: resolve by secret, per-person answering.
5. Dashboard figures.
6. Templates.
7. Full test run, then a live sandbox test on group L000138TR (parent plus three
   participants) with every link opened and submitted.
8. Written summary with screenshots for Ali.

## Release

Check-only validation, then a quick deploy after 15.10.2026 on Ali's explicit go.
Rollback: revert the code; the new fields and any collected answers stay valid.

## Open points

- Travellers without an email (8 of 101 in production): show them somewhere so the team
  can add addresses?
- Data protection: more guests receive email; the guest privacy note should be checked
  once more before release.
