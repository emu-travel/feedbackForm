/**
 * GxFeedbackRunNotice
 *
 * Tells the team when the nightly run could not ask a guest it should have
 * asked, so a refused booking does not wait quietly in the background job list
 * where nobody looks.
 *
 * One email per run, only when something needs attention, to the alert copy
 * address (Alert_Copy_Email__c). A booking the org refused to save is tried
 * again every night, so the notice repeats until the booking is fixed. A
 * booking saved as invited whose email then failed is not tried again by
 * itself, and the notice says how to resend it. Without a copy address the
 * problem is only written to the debug log.
 */
public with sharing class GxFeedbackRunNotice {
  /** Every notice built, so tests can read what went out. */
  @TestVisible
  private static List<Messaging.SingleEmailMessage> sent = new List<Messaging.SingleEmailMessage>();

  @TestVisible
  private static Boolean sandboxOverride;

  private static final String RESEND_SCRIPT = 'scripts/apex/send-feedback-invitation.apex';

  /** requests and results line up one to one, as GxFeedbackSender returns them. */
  public static void sendIfNeeded(
    List<GxFeedbackSender.Request> requests,
    List<GxFeedbackSender.Result> results
  ) {
    List<Problem> problems = new List<Problem>();
    for (Integer i = 0; i < results.size(); i++) {
      GxFeedbackSender.Result r = results[i];
      if (r == null || r.needsAttention != true) {
        continue;
      }
      Id bookingId = i < requests.size() &&
        requests[i] != null
        ? requests[i].bookingId
        : null;
      problems.add(new Problem(bookingId, r));
    }
    if (problems.isEmpty()) {
      return;
    }

    for (Problem p : problems) {
      System.debug(
        LoggingLevel.ERROR,
        'Golf Extra Feedback: ' + p.bookingNumber + ' not asked - ' + p.reason
      );
    }

    String copy = GxFeedbackSettings.alertCopyEmail();
    if (String.isBlank(copy)) {
      return;
    }

    Boolean sandbox = isSandbox();
    Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
    mail.setToAddresses(new List<String>{ copy });
    Id sender = senderId();
    if (sender != null) {
      mail.setOrgWideEmailAddressId(sender);
    }
    mail.setSaveAsActivity(false);
    mail.setSubject((sandbox ? '[Sandbox] ' : '') + subjectOf(problems.size()));
    mail.setHtmlBody(htmlOf(problems, sandbox));
    mail.setPlainTextBody(textOf(problems));

    sent.add(mail);
    List<Messaging.SendEmailResult> out = Messaging.sendEmail(
      new List<Messaging.SingleEmailMessage>{ mail },
      false
    );
    if (!out.isEmpty() && !out[0].isSuccess()) {
      System.debug(
        LoggingLevel.ERROR,
        'Golf Extra Feedback: notice not sent - ' + out[0].getErrors()
      );
    }
  }

  // ------------------------------------------------------------------
  // Content

  @TestVisible
  private static String subjectOf(Integer count) {
    return 'Golf Extra Feedback: ' +
      count +
      (count == 1 ? ' guest was' : ' guests were') +
      ' not asked this morning';
  }

  private static String htmlOf(List<Problem> problems, Boolean sandbox) {
    String base = URL.getOrgDomainUrl().toExternalForm();
    List<String> html = new List<String>();
    html.add(
      '<div style="font-family:Arial,Helvetica,sans-serif;font-size:14px;color:#10231a;max-width:620px">'
    );
    if (sandbox) {
      html.add(
        '<p style="background:#fbf0d6;padding:8px 12px;border-radius:4px">Sent from a sandbox.</p>'
      );
    }
    html.add(
      '<p>The nightly feedback run could not send ' +
        (problems.size() == 1
          ? 'this invitation or reminder'
          : 'these invitations or reminders') +
        '. Everyone else due today was sent as normal.</p>'
    );
    for (Problem p : problems) {
      String name = esc(
        p.bookingNumber == null ? 'A booking' : p.bookingNumber
      );
      String link = p.bookingId == null
        ? name
        : '<a href="' +
          base +
          '/lightning/r/Booking__c/' +
          p.bookingId +
          '/view">' +
          name +
          '</a>';
      html.add(
        '<p style="margin:14px 0 4px"><b>' +
          link +
          '</b> &nbsp;·&nbsp; ' +
          esc(p.kind) +
          '</p>' +
          '<p style="margin:0 0 4px;padding-left:10px;border-left:3px solid #dde3df">' +
          esc(p.reason) +
          '</p>' +
          '<p style="margin:0;color:#5a6b62">' +
          esc(p.nextStep) +
          '</p>'
      );
    }
    html.add('</div>');
    return String.join(html, '');
  }

  private static String textOf(List<Problem> problems) {
    String base = URL.getOrgDomainUrl().toExternalForm();
    List<String> lines = new List<String>{
      'The nightly feedback run could not send the following. Everyone else due today was sent as normal.'
    };
    for (Problem p : problems) {
      lines.add('');
      lines.add(
        (p.bookingNumber == null ? 'A booking' : p.bookingNumber) +
          ' - ' +
          p.kind
      );
      lines.add(p.reason);
      lines.add(p.nextStep);
      if (p.bookingId != null) {
        lines.add(base + '/lightning/r/Booking__c/' + p.bookingId + '/view');
      }
    }
    return String.join(lines, '\n');
  }

  private class Problem {
    public Id bookingId;
    public String bookingNumber;
    public String kind;
    public String reason;
    public String nextStep;

    Problem(Id bookingId, GxFeedbackSender.Result r) {
      this.bookingId = bookingId;
      this.bookingNumber = r.bookingNumber;
      this.kind = r.reminder == true ? 'Reminder' : 'Invitation';
      this.reason = String.isBlank(r.message) ? 'No reason given' : r.message;
      if (r.triedAgainNextRun == true) {
        this.nextStep = 'Nothing was changed on the booking. It is tried again at the next 07:00 run, so once the booking can be saved the guest is asked without anyone doing anything.';
      } else {
        this.nextStep =
          'The booking is already marked as ' +
          (r.reminder == true ? 'reminded' : 'invited') +
          ', so it is not tried again by itself. Once the cause is fixed, resend it with ' +
          RESEND_SCRIPT +
          '.';
      }
    }
  }

  // ------------------------------------------------------------------
  // Helpers

  private static String esc(String value) {
    return value == null ? '' : value.escapeHtml4();
  }

  private static Boolean isSandbox() {
    if (sandboxOverride != null) {
      return sandboxOverride;
    }
    return [SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox;
  }

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
