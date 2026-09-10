/*
 * Runs one pass of the nightly feedback dispatch, right now, in the foreground.
 *
 * This is the real production path - the same call GxFeedbackScheduler makes on
 * its schedule - so what it does here is exactly what the job will do at 07:00.
 * It really does send email. Check Setup > Email > Deliverability first: a
 * sandbox set to "System email only" will report success and deliver nothing.
 *
 *   sf apex run --target-org gx-sandbox --file scripts/apex/run-feedback-dispatch-once.apex
 */
List<GxFeedbackSender.Result> results = GxFeedbackScheduler.run();

System.debug('=== Feedback dispatch: ' + results.size() + ' booking(s) considered');
for (GxFeedbackSender.Result r : results) {
  System.debug(
    (r.sent ? 'SENT    ' : 'SKIPPED ') +
    (r.sent ? r.surveyUrl : r.message)
  );
}
