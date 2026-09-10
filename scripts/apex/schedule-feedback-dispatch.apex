/*
 * Schedules the nightly feedback dispatch at 07:00 org time.
 *
 * Run once per org. To confirm afterwards, or to find the job id to abort:
 *   SELECT Id, CronJobDetail.Name, NextFireTime, State FROM CronTrigger
 *
 *   sf apex run --target-org gx-sandbox --file scripts/apex/schedule-feedback-dispatch.apex
 */
String jobId = System.schedule(
  'Golf Extra Feedback',
  '0 0 7 * * ?',
  new GxFeedbackScheduler()
);

System.debug('Scheduled Golf Extra Feedback as ' + jobId);
