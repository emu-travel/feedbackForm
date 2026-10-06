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

    @InvocableVariable(
      label='Traveler Id'
      description='The traveller row this invitation comes from, when it comes from one.'
    )
    public Id travelerId;

    @InvocableVariable(
      label='Contact Id'
      description='The person to ask. Empty means the booking\'s main contact.'
    )
    public Id contactId;
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

    @InvocableVariable(
      label='Traveler Id'
      description='The traveller this result is about. Empty when it was the booking\'s main contact.'
    )
    public Id travelerId;

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
      p.travelerId = r == null ? null : r.travelerId;
      p.contactId = r == null ? null : r.contactId;
      p.allowResend = r != null && r.allowResend == true;
      p.markReminder = r != null && r.markReminder == true;
      toPrepare.add(p);
    }

    List<GxFeedbackDispatch.Result> prepared = GxFeedbackDispatch.prepare(
      toPrepare
    );

    Map<String, Id> templates = templateIds();
    Id senderId = senderId();
    Map<Id, String> bookingLinks = bookingLinksFor(prepared);

    List<Messaging.SingleEmailMessage> outbox = new List<Messaging.SingleEmailMessage>();
    List<Result> awaitingSend = new List<Result>();

    for (Integer i = 0; i < prepared.size(); i++) {
      GxFeedbackDispatch.Result p = prepared[i];
      Result out = new Result();
      out.surveyUrl = p.surveyUrl;
      out.bookingNumber = p.bookingNumber;
      out.travelerId = requests[i] == null ? null : requests[i].travelerId;
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
      // The Contact makes Recipient merge fields resolve - so the greeting is
      // this traveller's, not the booking's main contact's - and the booking
      // makes Booking__c ones resolve.
      mail.setTargetObjectId(p.recipientContactId);
      mail.setWhatId(requests[i].bookingId);
      mail.setSaveAsActivity(true);
      Boolean ownLink =
        String.isNotBlank(p.surveyUrl) &&
        p.surveyUrl != bookingLinks.get(requests[i].bookingId);
      if (!ownLink) {
        mail.setTemplateId(templateId);
      } else {
        // A traveller has a link of their own, but the template can only merge
        // the booking's. So the template is rendered here and that one link is
        // swapped for theirs; everything else about the email is unchanged.
        Messaging.SingleEmailMessage rendered = Messaging.renderStoredEmailTemplate(
          templateId,
          p.recipientContactId,
          requests[i].bookingId
        );
        String bookingLink = bookingLinks.get(requests[i].bookingId);
        mail.setSubject(rendered.getSubject());
        mail.setHtmlBody(
          personalise(rendered.getHtmlBody(), bookingLink, p.surveyUrl)
        );
        mail.setPlainTextBody(
          personalise(rendered.getPlainTextBody(), bookingLink, p.surveyUrl)
        );
      }
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

  /**
   * The booking's own survey link, for the trips that are inviting a traveller.
   * It is what the template merges, and what the traveller's link replaces.
   */
  private static Map<Id, String> bookingLinksFor(
    List<GxFeedbackDispatch.Result> prepared
  ) {
    Set<Id> bookingIds = new Set<Id>();
    for (GxFeedbackDispatch.Result p : prepared) {
      if (p.ok && p.bookingId != null) {
        bookingIds.add(p.bookingId);
      }
    }
    Map<Id, String> links = new Map<Id, String>();
    if (bookingIds.isEmpty()) {
      return links;
    }
    for (Booking__c b : [
      SELECT Id, Survey_Link__c
      FROM Booking__c
      WHERE Id IN :bookingIds
    ]) {
      links.put(b.Id, b.Survey_Link__c);
    }
    return links;
  }

  /**
   * Swaps the booking's link for this traveller's. Every occurrence, because
   * the templates carry it on the button, on the fallback line beneath it and
   * in the plain text part - and all three have to lead to the same person's
   * survey. The body is returned untouched when there is nothing to swap, so a
   * missing link is visible as a missing link rather than silently sending
   * somebody else's.
   */
  @TestVisible
  private static String personalise(
    String body,
    String bookingLink,
    String personLink
  ) {
    if (
      String.isBlank(body) ||
      String.isBlank(bookingLink) ||
      String.isBlank(personLink)
    ) {
      return body;
    }
    // The secret, not the whole address. A rendered template writes the link
    // into HTML as ...&amp;k=..., so looking for the address as the database
    // spells it finds nothing and every guest is sent the booking's own link.
    // The secret itself is letters, digits, dash and underscore, which no
    // encoding touches, so swapping that works in the HTML and the plain text
    // alike.
    String bookingSecret = secretIn(bookingLink);
    String personSecret = secretIn(personLink);
    if (String.isNotBlank(bookingSecret) && String.isNotBlank(personSecret)) {
      return bookingSecret == personSecret
        ? body
        : body.replace(bookingSecret, personSecret);
    }
    return body.replace(bookingLink, personLink);
  }

  /** The k= token of a survey link, or null if there is not one. */
  @TestVisible
  private static String secretIn(String url) {
    if (String.isBlank(url) || !url.contains('k=')) {
      return null;
    }
    Matcher m = Pattern.compile('^[A-Za-z0-9_-]+')
      .matcher(url.substringAfter('k='));
    return m.find() ? m.group(0) : null;
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
