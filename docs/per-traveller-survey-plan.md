# Per-traveller feedback invitations (incl. group and PRO trips)

Every traveller gets their own survey link, built from their own itinerary. Decided
with Ali on 28.09.2026, built and tested in the staging sandbox on 29.09.2026.
Production release only after the 15.10.2026 go-live, on Ali's explicit go.

Status: **built and live-tested in the sandbox**. Production is untouched, and `main`
still matches it.

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

- A group trip is **several Booking\_\_c records**: the parent (record type PRO) and one
  participant booking per party, linked by `TravelGroup__c`.
- **BookingNumber\_\_c is not unique**: parent and participants share it (P000378ES
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
   contact when not already among them. Duplicates removed by contact id, then by
   lower-cased email - the org auto-creates a traveller row for the main contact, so
   without the second pass that person would be asked twice.
2. **Group trips**: participants are invited from their own participant booking. The
   group parent invites only its own main contact (the pro or organiser), and only if
   that person was not already invited as a participant or traveller.
3. **Itinerary**: the snapshot is taken from the booking the person was invited from,
   with the group fallback described above.
4. **Link**: `?b=<booking number>&k=<secret>` stays, but the **secret alone** resolves
   the person, because the number is not unique. The number is still checked against
   the trip the secret resolved to, so a mismatched pair is refused.
5. **Answering**: refused only when that person has already answered.
6. **Status**: first answer moves that booking to Feedback.
7. **Reminders**: per person, one each.

## Where an invitation lives: `Feedback_Invitation__c`

One row per invited person. Created by `GxFeedbackDispatch` just before the email
leaves, and it is what the public survey reads.

| Field              | Type                             | Purpose                                |
| ------------------ | -------------------------------- | -------------------------------------- |
| `Secret__c`        | Text(64), unique, case sensitive | the person's own link                  |
| `Sent_On__c`       | Date/Time                        | when they were invited                 |
| `Reminder_Sent__c` | Checkbox                         | one reminder ever                      |
| `Answered_On__c`   | Date/Time                        | when they answered                     |
| `Booking__c`       | Lookup (Booking, required)       | the trip this person answers for       |
| `Contact__c`       | Lookup (Contact)                 | the person                             |
| `Traveler__c`      | Lookup (Traveler)                | the traveller row it came from, if any |
| `Survey_Link__c`   | Formula (Text)                   | the ready-made link, for the team      |

**Why a separate object rather than fields on `Traveler__c`.** The plan first put these
fields on the traveller row. That cannot work: `Traveler__c` is a detail of **Contact**,
so its sharing is controlled by the contact. Giving the public guest user access to
traveller rows would mean opening customer contacts to it, and Salesforce refuses the
sharing rule outright ("org wide default is Controlled By Parent"). The invitation
object is private, shares nothing but itself, and the guest user reads it through one
criteria-based rule: `Sent_On__c` is not empty, so only invitations that were really
sent are visible. **The survey never reads a Contact record.**

The booking keeps `Form_Secret__c`, `SurveySent__c` and `Survey_Sent_On__c`, so a trip
still knows it entered the programme.

**Legacy trips** invited before this change have no invitation rows. They keep working:
their main contact is judged and reminded from the booking exactly as before, and the
survey window guard treats a booking already stamped as invited as inside the
programme. Both fallbacks are covered by tests.

The five `Survey_*` fields added to `Traveler__c` in the first commit are **no longer
used by any code**. They are still in the repo and the sandbox, and can be removed in a
separate clean-up once Ali confirms.

## Class changes (as built)

1. **GxFeedbackScheduler** - also selects participant bookings whose group parent is
   Traveled or Completed; builds one request per traveller with an email plus the main
   contact; the reminder pass reads `Feedback_Invitation__c` (sent, not reminded, not
   answered) with a booking-level fallback for legacy trips.
2. **GxFeedbackDispatch** - takes a traveller and contact per request, mints a secret
   per person, upserts the invitation only for bookings that actually saved, snapshots
   per booking, and judges booking status only when a trip **enters** the programme, so
   one guest answering does not lock the others out. New refusal reason for a booking
   with no reachable email.
3. **GxFeedbackSender** - one email per recipient. The template can only merge the
   booking's link, so for a personal link the email is rendered and that one link is
   swapped for the person's; everything else about the email is unchanged. The
   recipient contact is set on the message, so the greeting is the traveller's own.
4. **GxFeedbackService** - resolves the invitation by secret, checks the booking number
   against it, refuses only when **that person** already answered, writes the response
   against the right contact and booking, and stamps `Answered_On__c`.
5. **GxFeedbackDashboardController** - counts guests asked and guests answered, with
   trips invited and trips answered kept alongside.
6. **Dashboard (gxDashboardView)** - the tiles read "N guests asked" and the rate shows
   "N of M trips" beneath it.
7. **Permission sets** - `Golf_Extra_Feedback_Guest` gets read on the invitation and on
   Secret, Sent On, Answered On and Contact. `Golf_Extra_Feedback_Admin` gets the object
   and its fields, without which the fields exist but are invisible even to an admin.

## Live sandbox test (29.09.2026)

Group trip `GX-TRAV-LIVE`: a PRO group booking plus two participant bookings, one guest
each, a hotel each, and a golf round on one party only.

- The nightly run produced **three invitations with three different links**: the two
  travellers and the organiser. Nobody was asked twice.
- The traveller's link opened on the real sandbox site and showed **his own** itinerary,
  including the golf round the other guest does not have.
- Two guests answered the same trip: FB-00046 (overall 9, NPS 10) and FB-00047
  (overall 6, NPS 5), each stored against the right contact and the right party booking.
- After answering, that guest's link reported "submitted" while the organiser's stayed
  open. Both party bookings moved to Feedback; the group booking stayed Completed.
- Dashboard: 30 responses, 33 guests asked, 91 % rate, 33 trips invited, 30 answered,
  NPS 70.0, 1 open follow-up.
- 177 Apex tests and 64 dashboard Jest tests pass.

## Edge-case round (29.09.2026)

A second sandbox round, on trips built to break the design rather than to
demonstrate it: a duplicate contact, two travellers sharing one inbox, a couple
on one booking, a guest with no address, a party with no lines, the same guest on
two trips, a trip too old, a trip that only ended today, a ten-party group, and
nine mangled or stolen links.

**Held up without changes**

- Link handling. A made-up secret, another trip's number, a secret in the wrong
  case, a truncated one, one with a trailing space, a blank one, a quoted SOQL
  fragment and another guest's secret on this trip: all nine refused as
  "invalid", none threw.
- Two travellers sharing one inbox are asked once, whatever case the address is
  written in.
- A guest with no address is skipped, and the trip still asks everyone else.
- The same guest on two trips gets two links, each resolving to its own trip.
- A trip older than the age cap is not asked; a trip that ended today waits out
  its 36 hours.
- Answering closes only that guest: a second submission on the same link is
  refused, the guest beside them stays open, and the reminder pass then reminds
  the silent one and leaves the one who answered alone. A second reminder night
  writes to nobody.
- A ten-party group, 21 guests: 21 invitations in one run, 19 of 100 SOQL
  queries, 3 DML statements, 258 ms of CPU.

**Four things it broke, now fixed**

1. **The wrong person's name.** `getContext` built its `guestName` from the
   booking's main contact, so the second traveller on a booking came back as the
   first one. No screen renders that field today, so no guest saw it, but the
   survey's own contract was wrong. The name is now stamped on each invitation
   (`Guest_Name__c`) as it is prepared, and read from there. It has to be stored,
   because the public survey may never read a Contact.
2. **Expiry measured from the trip, not the guest.** Validity counted from the
   booking's `Survey_Sent_On__c`, which is whenever anyone on that trip was last
   asked. A guest invited today on a trip asked a fortnight ago was told their
   link had expired; a guest whose own link was long dead got it back because
   somebody else was reminded. It now counts from the guest's own invitation,
   falling back to the booking for links minted before invitations existed.
3. **A guest added later was never asked.** The invitation pass only looks at
   trips nobody has been asked about, so adding a traveller after the invitations
   went out - or filling in the address the run notice asked for - achieved
   nothing. A `latecomers()` pass now asks them on the next run. It only
   considers trips that already carry invitations, so trips invited before this
   existed behave exactly as they did.
4. **A party with no lines got no survey at all.** The documented group fallback
   had never been built: a participant booking carrying no rateable line was
   refused with "nothing on this itinerary can be rated". It now falls back to
   the group booking's lines, and only when the party holds nothing of its own.

## Booking status on a group trip (29.09.2026)

The status bar was checked on both Booking record types, through the whole
lifecycle, on the real record pages.

- **FIT** (record type `Booking`): Traveled -> Completed when the invitation is
  sent -> Feedback when the guest answers. The bar follows every step.
- **Group trip** (record type `PRO`): its path has no Traveled step at all, so it
  stays at Completed until its organiser answers, then moves to Feedback.

**A party booking was the gap.** It is invited through its group's status while
still sitting at its own commercial status, so it went straight from Accepted to
Feedback, never passing Traveled or Completed. The survey code was deliberately
not changed for this: pushing a party from Calculation to Completed would hide
that nothing was ever agreed for it, and a status write wakes the org's booking
flows, which can fail and cost that guest their invitation.

Instead there is a scheduled flow of its own, `Gx - Mark Group Parties Travelled`,
running nightly at 00:30 local - after the org's own
`ScheduleFlow - Mark Booking Status Travelled` at 00:15, and well before the
feedback job. For each party whose group is Traveled, Completed or Feedback, and
whose own end date has passed, it sets the party to Traveled. The survey then
takes it on as it does any other trip.

It leaves alone any party at Calculation, Offered or Discussion, where nothing was
agreed, and anything Rejected or Canceled. It also checks the record type, because
Traveled does not exist on the PRO path.

Verified in the sandbox: parties at Accepted, Booked, Invoiced and Paid all moved
to Traveled; Calculation, Offered, Discussion, Rejected and Canceled did not; a
party under a group that had not travelled did not; and one party was followed the
whole way, Accepted -> Traveled -> Completed -> Feedback.

**Worth knowing about this org**

- `Status__c` is a restricted picklist **and** record-type filtered through the
  API: a PRO booking cannot hold Traveled at all, and a Booking cannot hold
  Confirmed or LT booked. A write of the wrong value fails rather than corrupting
  the record.
- The org's own nightly flow promotes only from **Paid**, and does not filter by
  record type. A group booking sitting at Paid when its end date passes will make
  that flow fail, since PRO cannot hold Traveled. One for Irfan.
- A party booking inherits its group's booking number, and its dates were
  overwritten to the group's when created.

## How a group trip reaches the survey (06.10.2026)

Agreed with Ali and Irfan: the PRO record type will not get a "Traveled" step.
Its path runs Paid -> Completed -> Feedback, so **Completed does for a group
booking what Traveled does for an ordinary one**. The survey needed no change
for this: it has always accepted Traveled or Completed as "this trip happened".

What was missing was anything to move a group booking there. Two scheduled flows
now carry a finished group trip to the survey, ten minutes apart:

| When (Berlin) | Flow                                | What it does                                                  |
| ------------- | ----------------------------------- | ------------------------------------------------------------- |
| 00:20         | `Gx - Mark Group Trips Completed`   | A PRO booking whose end date has passed goes to **Completed** |
| 00:30         | `Gx - Mark Group Parties Travelled` | Its parties then go to **Traveled**                           |
| 07:00         | `GxFeedbackScheduler`               | Everyone on the trip is invited                               |

Both leave alone anything still at Calculation, Offered or Discussion, where
nothing was agreed, and anything Rejected or Canceled. Both check the record
type, because Traveled does not exist on the PRO path and Salesforce refuses it
there outright.

Verified in the sandbox on a group at "LT booked" that had ended: it moved to
Completed, three controls did not move (a group still at Calculation, one whose
trip has not ended, and an ordinary FIT booking), and the nightly run then
invited the organiser on the group booking and the guest on the party.

**One consequence for the team:** on a PRO booking, Completed means both "the
trip is over" and "the survey has gone out", because the path has one step
fewer. The booking's Survey Sent On field, or its invitations, are where to look
for the difference.

## Getting it into production (06.10.2026)

Deployed in steps, because a brand-new object and the Apex that reads it cannot
go in one go: the deploying user has no access to fields that did not exist a
moment earlier, so every test touching them fails. The first full validation
failed exactly that way, 98 tests of 169.

| Step | What                                                                                            | State                              |
| ---- | ----------------------------------------------------------------------------------------------- | ---------------------------------- |
| 1    | The object, its fields, both permission sets, the guest sharing rule. No Apex, so no tests run. | **live in production**             |
| 2    | `Golf_Extra_Feedback_Admin` assigned to Ali and Kaan.                                           | **done**                           |
| 3    | Apex, the two nightly flows, the dashboard component.                                           | **live in production, 06.10.2026** |

Step 3 validated with 1103 tests and no failures, and went in the same day.

Manifests for each step are in `release/per-traveller/`. They deliberately leave
out the Account and Booking sharing rules, which already exist in production and
would only set off a sharing recalculation, and the five unused `Traveler__c`
survey fields.

**Flows reach production as Draft, whatever the metadata says.** Both nightly
flows arrived inactive and would simply never have run, with nothing reporting
it. The validation had suggested otherwise, which is worth remembering: a
validation says a flow can be deployed, not that it will be active. They were
activated afterwards through their flow definitions (`FlowDefinition` carrying
`activeVersionNumber`, deployed at API 43.0, the Tooling endpoint not being
reachable from the CLI here). Any flow deployed to production needs the same
step, and needs checking rather than assuming.

`GxFeedbackScheduler` deployed cleanly despite already being scheduled, which
was the other risk and did not materialise.

What runs each night in production now:

| Berlin | Job                               |
| ------ | --------------------------------- |
| 00:20  | Gx - Mark Group Trips Completed   |
| 00:30  | Gx - Mark Group Parties Travelled |
| 07:00  | Golf Extra Feedback               |

Deployed on a day when all three provably had nothing to do: 0 trips due, 0
parties to promote, 0 group trips to complete. The first guest email cannot go
out before 17.10.2026, a trip ending on the 15th plus the 36 hour wait.

Also learned: the six `AccountEngagementTravelRequest` tests that fail in the
sandbox pass in production, so the full local suite is usable there.

## Release

Check-only validation, then a quick deploy after 15.10.2026 on Ali's explicit go.
The deploy carries the new object, its fields, the sharing rule, both permission sets
and the classes. After deploying, the site has to be published so the guest user picks
up the new access.

Rollback: revert the code. The invitation object and any collected answers stay valid,
and the booking-level fallbacks mean a reverted org still invites main contacts.

## Before go-live - decisions Ali has to make

- [x] **Schedule the nightly job in production.** Done 06.10.2026: "Golf Extra
      Feedback" runs daily at 07:00 Berlin. It is inert until a trip ends on or
      after the start date, so the first invitation cannot go out before
      17.10.2026 (a trip ending on the 15th, plus the 36 hour wait). Scheduled
      early on purpose: it was the one gap that would have let go-live pass with
      nothing sent and nothing saying so, and it doubles as the fallback - if
      the per-traveller release is not deployed by 15.10, the programme still
      starts on time with one invitation per booking.

- [ ] **Tell the team about `Auto Assign All Travelers`.** Decided 06.10.2026:
      the automation stays as it is, and the team is told instead. The survey
      now asks each guest only about the services they are recorded as being
      on, so when a service belongs to part of the party only, that checkbox
      has to be unticked on it and just those people assigned. Left ticked, the
      whole party is asked about it. Proportionate because it is the exception:
      of 28 production trips with two or more travellers, 26 share every
      service and only 2 split them. Ali is sending this to the team.

- [ ] **Fill in the 8 travellers in production who have no email address**, or
      accept that they are never asked.
- [ ] **Check the guest privacy note**, since more guests now receive email.
- [x] **The golf pro is asked, about his own trip.** Decided 06.10.2026: he
      travels with the group, stays in the hotel and plays, so he is a guest
      like any other. No change was needed - he is already invited on the group
      booking, which carries the package he travelled on, and he is asked once,
      never again as a participant.

## Open points

- Travellers without an email: show them somewhere so the team can add addresses?
- Remove the unused `Traveler__c` survey fields, and tidy the sandbox test data
  (GX-TRAV-LIVE trip, its contacts, invitations and responses).
