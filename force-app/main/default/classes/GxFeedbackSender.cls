/**
 * GxFeedbackSender
 *
 * Sends the post-trip feedback invitation. Prepares each booking through
 * GxFeedbackDispatch first, so the token exists and the booking is readable by
 * the guest before the email carrying its link leaves.
 *
 * Invocable so the same path serves both ways surveys go out: the nightly
 * GxFeedbackScheduler, and the Send Feedback Survey button a travel designer
 * uses for a one-off or a resend.
 */
public with sharing class GxFeedbackSender {
  @TestVisible
  private static final String TEMPLATE = 'Gx_Feedback_Invitation';

  /** The follow-up, for a guest who was invited and stayed silent. */
  @TestVisible
  private static final String REMINDER_TEMPLATE = 'Gx_Feedback_Reminder';

  public class Request {
    @InvocableVariable(label='Booking Id' required=true)
    public Id bookingId;

    @InvocableVariable(
      label='Allow Resend'
      description='Set when a person is deliberately re-sending an invitation.'
    )
    public Boolean allowResend = false;

    @InvocableVariable(
      label='Mark As Reminder'
      description='Set by the nightly reminder pass, so a guest is only ever reminded once.'
    )
    public Boolean markReminder = false;
  }

  public class Result {
    @InvocableVariable(label='Sent')
    public Boolean sent = false;

    @InvocableVariable(
      label='Message'
      description='Why the invitation was not sent, when it was not.'
    )
    public String message;

    @InvocableVariable(label='Survey URL')
    public String surveyUrl;

    @InvocableVariable(label='Booking Number')
    public String bookingNumber;

    @InvocableVariable(label='Reminder')
    public Boolean reminder = false;

    /**
     * Due, but not sent for a reason someone has to act on: the booking could
     * not be saved, or the email itself failed. Not set for the ordinary
     * reasons a booking waits, such as a trip still inside its waiting period.
     */
    @InvocableVariable(label='Needs Attention')
    public Boolean needsAttention = false;

    /**
     * The booking was left untouched, so the next nightly run picks it up again
     * by itself. False when it needs attention after being saved as invited.
     */
    @InvocableVariable(label='Tried Again Next Run')
    public Boolean triedAgainNextRun = false;
  }

  @InvocableMethod(
    label='Send Golf Extra Feedback Invitation'
    description='Prepares the booking and emails the guest their personal survey link. Reports why nothing was sent when a booking is not eligible.'
    category='Golf Extra Feedback'
  )
  public static List<Result> send(List<Request> requests) {
    List<Result> results = new List<Result>();
    if (requests == null || requests.isEmpty()) {
      return results;
    }

    List<GxFeedbackDispatch.Request> toPrepare = new List<GxFeedbackDispatch.Request>();
    for (Request r : requests) {
      GxFeedbackDispatch.Request p = new GxFeedbackDispatch.Request();
      p.bookingId = r == null ? null : r.bookingId;
      p.allowResend = r != null && r.allowResend == true;
      p.markReminder = r != null && r.markReminder == true;
      toPrepare.add(p);
    }

    List<GxFeedbackDispatch.Result> prepared = GxFeedbackDispatch.prepare(
      toPrepare
    );

    Map<String, Id> templates = templateIds();
    Id senderId = senderId();

    List<Messaging.SingleEmailMessage> outbox = new List<Messaging.SingleEmailMessage>();
    List<Result> awaitingSend = new List<Result>();

    for (Integer i = 0; i < prepared.size(); i++) {
      GxFeedbackDispatch.Result p = prepared[i];
      Result out = new Result();
      out.surveyUrl = p.surveyUrl;
      out.bookingNumber = p.bookingNumber;
      // A reminder is a different email, not the same one sent twice.
      Boolean reminding =
        requests[i] != null &&
        requests[i].markReminder == true;
      out.reminder = reminding;

      if (!p.ok) {
        out.message = p.skippedReason;
        out.needsAttention = p.saveFailed == true;
        out.triedAgainNextRun = p.saveFailed == true;
        results.add(out);
        continue;
      }

      String wanted = reminding ? REMINDER_TEMPLATE : TEMPLATE;
      Id templateId = templates.get(wanted);
      // Both of these are found only after the booking was saved as invited,
      // so the guest will not be asked again on their own.
      if (templateId == null) {
        out.message = 'Email template ' + wanted + ' not found';
        out.needsAttention = true;
        results.add(out);
        continue;
      }
      if (String.isBlank(p.surveyUrl)) {
        out.message = 'No survey base URL configured, so there is no link to send';
        out.needsAttention = true;
        results.add(out);
        continue;
      }

      Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
      mail.setTemplateId(templateId);
      // The Contact makes Recipient merge fields resolve; the booking makes
      // Booking__c ones - including the survey link - resolve.
      mail.setTargetObjectId(p.recipientContactId);
      mail.setWhatId(requests[i].bookingId);
      mail.setSaveAsActivity(true);
      if (senderId != null) {
        mail.setOrgWideEmailAddressId(senderId);
      }

      outbox.add(mail);
      awaitingSend.add(out);
      results.add(out);
    }

    if (!outbox.isEmpty()) {
      List<Messaging.SendEmailResult> sendResults = Messaging.sendEmail(
        outbox,
        false
      );
      for (Integer i = 0; i < sendResults.size(); i++) {
        Result out = awaitingSend[i];
        if (sendResults[i].isSuccess()) {
          out.sent = true;
        } else {
          out.message = firstError(sendResults[i]);
          out.needsAttention = true;
        }
      }
    }

    return results;
  }

  private static String firstError(Messaging.SendEmailResult r) {
    List<Messaging.SendEmailError> errors = r.getErrors();
    return errors.isEmpty()
      ? 'The email could not be sent'
      : errors[0].getMessage();
  }

  /**
   * Both templates in one query, looked up by developer name so the same code
   * works in every org without an id to configure.
   */
  private static Map<String, Id> templateIds() {
    Map<String, Id> byName = new Map<String, Id>();
    for (EmailTemplate t : [
      SELECT Id, DeveloperName
      FROM EmailTemplate
      WHERE DeveloperName IN (:TEMPLATE, :REMINDER_TEMPLATE)
    ]) {
      byName.put(t.DeveloperName, t.Id);
    }
    return byName;
  }

  /** Null falls back to the running user, which is correct for a manual send. */
  private static Id senderId() {
    String address = GxFeedbackSettings.senderEmail();
    if (String.isBlank(address)) {
      return null;
    }
    List<OrgWideEmailAddress> found = [
      SELECT Id
      FROM OrgWideEmailAddress
      WHERE Address = :address
      LIMIT 1
    ];
    return found.isEmpty() ? null : found[0].Id;
  }
}
