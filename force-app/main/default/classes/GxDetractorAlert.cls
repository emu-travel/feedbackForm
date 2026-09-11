/**
 * GxDetractorAlert
 *
 * Tells the travel designer at once when a guest answers "would you recommend
 * us" with 6 or below, so the call happens while the trip is fresh - not when
 * someone next opens the dashboard.
 *
 * Two halves, deliberately apart:
 *   raise()  runs inside the guest's submission. It only publishes
 *            Gx_Detractor_Alert__e, which is published after commit: a failed
 *            submission alerts nobody, and a failed email can never cost the
 *            guest their answer.
 *   send()   runs from GxDetractorAlertTrigger as the Automated Process user.
 *            The guest user may not read User records, so the designer's
 *            address is looked up here, outside the guest's context.
 *
 * Recipients: the trip's travel designer, with Alert_Copy_Email__c copied, or
 * the copy address alone when a trip has no designer. In a sandbox the
 * designer is never emailed - sandboxes carry real colleagues' addresses - and
 * the alert goes to the copy address only, marked [Sandbox].
 */
public without sharing class GxDetractorAlert {
  public static final Integer DETRACTOR_MAX = 6;
  private static final Integer LOW_SCORE = 7;

  /** Every alert built by send(), so tests can read what went out. */
  @TestVisible
  private static List<Messaging.SingleEmailMessage> sent = new List<Messaging.SingleEmailMessage>();

  @TestVisible
  private static Boolean sandboxOverride;

  /** Every response an alert was raised for, so tests can see it happened. */
  @TestVisible
  private static List<Id> raised = new List<Id>();

  /** Called from the survey submission, still as the guest. */
  public static void raise(Id responseId, Integer recommendation) {
    if (
      responseId == null ||
      recommendation == null ||
      recommendation > DETRACTOR_MAX ||
      !GxFeedbackSettings.detractorAlertsOn()
    ) {
      return;
    }
    raised.add(responseId);
    EventBus.publish(new Gx_Detractor_Alert__e(Response_Id__c = responseId));
  }

  /** Called from the event trigger, as the Automated Process user. */
  public static void send(List<Gx_Detractor_Alert__e> events) {
    if (!GxFeedbackSettings.detractorAlertsOn()) {
      return;
    }
    Set<Id> ids = new Set<Id>();
    for (Gx_Detractor_Alert__e e : events) {
      try {
        ids.add(Id.valueOf(e.Response_Id__c));
      } catch (Exception ignored) {
        // Not an id: nothing to alert about.
      }
    }
    if (ids.isEmpty()) {
      return;
    }

    Boolean sandbox = isSandbox();
    String copy = GxFeedbackSettings.alertCopyEmail();
    Id sender = senderId();

    List<Messaging.SingleEmailMessage> mails = new List<Messaging.SingleEmailMessage>();
    for (Feedback_Response__c r : [
      SELECT
        Id,
        Name,
        Recommendation_NPS__c,
        Overall_Experience__c,
        Overall_Experience_Comment__c,
        Consultation_Rating__c,
        Consultation_Comment__c,
        General_Hotel_Comment__c,
        General_Golf_Comment__c,
        Improvement_Suggestions__c,
        General_Feedback__c,
        Contact__r.Name,
        Contact__r.Email,
        Contact__r.Phone,
        Contact__r.MobilePhone,
        Booking__c,
        Booking__r.BookingNumber__c,
        Booking__r.Region__c,
        Booking__r.End_Date__c,
        Booking__r.TravelDesigner__r.Name,
        Booking__r.TravelDesigner__r.Email,
        Booking__r.TravelDesigner__r.IsActive,
        (
          SELECT Item_Name__c, Sub_Category__c, Score__c, Comment__c
          FROM Feedback_Ratings__r
          ORDER BY CreatedDate, Id
        )
      FROM Feedback_Response__c
      WHERE Id IN :ids
    ]) {
      List<String> to = new List<String>();
      List<String> cc = new List<String>();
      String designer = designerEmail(r);
      if (sandbox) {
        if (String.isNotBlank(copy)) {
          to.add(copy);
        }
      } else if (designer != null) {
        to.add(designer);
        if (String.isNotBlank(copy) && copy != designer) {
          cc.add(copy);
        }
      } else if (String.isNotBlank(copy)) {
        to.add(copy);
      }
      if (to.isEmpty()) {
        continue;
      }

      Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
      mail.setToAddresses(to);
      if (!cc.isEmpty()) {
        mail.setCcAddresses(cc);
      }
      if (sender != null) {
        mail.setOrgWideEmailAddressId(sender);
      }
      mail.setSaveAsActivity(false);
      mail.setSubject((sandbox ? '[Sandbox] ' : '') + subjectOf(r));
      mail.setHtmlBody(htmlOf(r, sandbox));
      mail.setPlainTextBody(textOf(r));
      mails.add(mail);
    }

    sent.addAll(mails);
    if (mails.isEmpty()) {
      return;
    }
    // allOrNone false: one bad address must not stop the other alerts.
    for (Messaging.SendEmailResult result : Messaging.sendEmail(mails, false)) {
      if (!result.isSuccess()) {
        System.debug(
          LoggingLevel.ERROR,
          'Detractor alert not sent: ' + result.getErrors()
        );
      }
    }
  }

  // ------------------------------------------------------------------
  // Content

  @TestVisible
  private static String subjectOf(Feedback_Response__c r) {
    return 'Unhappy guest: ' +
      guestOf(r) +
      ' would recommend us ' +
      score(r.Recommendation_NPS__c) +
      '/10 (' +
      r.Booking__r?.BookingNumber__c +
      ')';
  }

  private static String htmlOf(Feedback_Response__c r, Boolean sandbox) {
    String base = URL.getOrgDomainUrl().toExternalForm();
    String responseUrl =
      base +
      '/lightning/r/Feedback_Response__c/' +
      r.Id +
      '/view';
    String bookingUrl =
      base +
      '/lightning/r/Booking__c/' +
      r.Booking__c +
      '/view';

    List<String> html = new List<String>();
    html.add(
      '<div style="font-family:Arial,Helvetica,sans-serif;font-size:14px;color:#10231a;max-width:620px">'
    );
    if (sandbox) {
      html.add(
        '<p style="background:#fbf0d6;padding:8px 12px;border-radius:4px">' +
          'Sent from a sandbox. In production this goes to the travel designer' +
          esc(designerNote(r)) +
          '.</p>'
      );
    }
    html.add(
      '<p><b>' +
        esc(guestOf(r)) +
        '</b> has just answered the feedback survey for ' +
        esc(tripOf(r)) +
        ' and would recommend us <b>' +
        score(r.Recommendation_NPS__c) +
        ' out of 10</b>.</p>'
    );
    html.add(
      '<p>Overall trip: <b>' +
        score(r.Overall_Experience__c) +
        '</b> &nbsp;·&nbsp; Our consultation: <b>' +
        score(r.Consultation_Rating__c) +
        '</b></p>'
    );

    List<String> low = standout(r);
    if (!low.isEmpty()) {
      html.add('<p style="margin-bottom:4px"><b>What stood out</b></p><ul>');
      for (String line : low) {
        html.add('<li>' + esc(line) + '</li>');
      }
      html.add('</ul>');
    }

    List<String> words = wordsOf(r);
    if (!words.isEmpty()) {
      html.add('<p style="margin-bottom:4px"><b>In their words</b></p>');
      for (String line : words) {
        html.add(
          '<p style="margin:4px 0 8px;padding-left:10px;border-left:3px solid #dde3df">' +
            esc(line).replace('\n', '<br/>') +
            '</p>'
        );
      }
    }

    String contact = contactOf(r);
    if (contact != null) {
      html.add('<p>Contact: ' + esc(contact) + '</p>');
    }
    html.add(
      '<p><a href="' +
        responseUrl +
        '">Open the full response</a> &nbsp;·&nbsp; <a href="' +
        bookingUrl +
        '">Open the booking</a></p>'
    );
    html.add(
      '<p style="color:#5a6b62">Please get in touch with the guest, then record ' +
      'what you did under “Unhappy guests to follow up” on the Feedback Dashboard.</p>'
    );
    html.add('</div>');
    return String.join(html, '');
  }

  private static String textOf(Feedback_Response__c r) {
    List<String> lines = new List<String>{
      guestOf(r) +
      ' has just answered the feedback survey for ' +
      tripOf(r) +
      ' and would recommend us ' +
      score(r.Recommendation_NPS__c) +
      ' out of 10.',
      'Overall trip: ' +
      score(r.Overall_Experience__c) +
      ' · Our consultation: ' +
      score(r.Consultation_Rating__c)
    };
    List<String> low = standout(r);
    if (!low.isEmpty()) {
      lines.add('');
      lines.add('What stood out:');
      for (String line : low) {
        lines.add('- ' + line);
      }
    }
    List<String> words = wordsOf(r);
    if (!words.isEmpty()) {
      lines.add('');
      lines.add('In their words:');
      for (String line : words) {
        lines.add('"' + line + '"');
      }
    }
    String contact = contactOf(r);
    if (contact != null) {
      lines.add('');
      lines.add('Contact: ' + contact);
    }
    lines.add('');
    lines.add(
      'Open the full response: ' +
        URL.getOrgDomainUrl().toExternalForm() +
        '/lightning/r/Feedback_Response__c/' +
        r.Id +
        '/view'
    );
    return String.join(lines, '\n');
  }

  /** Every score below 7, the way the dashboard's "What stood out" lists them. */
  @TestVisible
  private static List<String> standout(Feedback_Response__c r) {
    List<String> out = new List<String>();
    addIfLow(out, 'The trip overall', r.Overall_Experience__c);
    addIfLow(out, 'Our consultation', r.Consultation_Rating__c);
    for (Feedback_Rating__c rating : r.Feedback_Ratings__r) {
      String label = String.isBlank(rating.Sub_Category__c)
        ? rating.Item_Name__c
        : rating.Item_Name__c + ' · ' + rating.Sub_Category__c;
      addIfLow(out, label, rating.Score__c);
    }
    return out;
  }

  private static void addIfLow(List<String> out, String label, Decimal value) {
    if (value != null && value < LOW_SCORE) {
      out.add(label + ': ' + score(value));
    }
  }

  /** What the guest wrote, labelled where the label adds something. */
  @TestVisible
  private static List<String> wordsOf(Feedback_Response__c r) {
    List<String> out = new List<String>();
    addText(out, null, r.Improvement_Suggestions__c);
    addText(out, 'About the trip', r.Overall_Experience_Comment__c);
    addText(out, 'About our consultation', r.Consultation_Comment__c);
    for (Feedback_Rating__c rating : r.Feedback_Ratings__r) {
      addText(out, rating.Item_Name__c, rating.Comment__c);
    }
    addText(out, 'About the hotels', r.General_Hotel_Comment__c);
    addText(out, 'About the golf', r.General_Golf_Comment__c);
    addText(out, null, r.General_Feedback__c);
    return out;
  }

  private static void addText(List<String> out, String about, String text) {
    if (String.isBlank(text)) {
      return;
    }
    out.add(about == null ? text.trim() : about + ': ' + text.trim());
  }

  // ------------------------------------------------------------------
  // Helpers

  private static String guestOf(Feedback_Response__c r) {
    return String.isBlank(r.Contact__r?.Name) ? 'A guest' : r.Contact__r.Name;
  }

  private static String tripOf(Feedback_Response__c r) {
    List<String> parts = new List<String>{ r.Booking__r?.BookingNumber__c };
    if (String.isNotBlank(r.Booking__r?.Region__c)) {
      parts.add(r.Booking__r.Region__c);
    }
    if (r.Booking__r?.End_Date__c != null) {
      parts.add('ended ' + r.Booking__r.End_Date__c.format());
    }
    return String.join(parts, ', ');
  }

  private static String contactOf(Feedback_Response__c r) {
    List<String> parts = new List<String>();
    if (String.isNotBlank(r.Contact__r?.Phone)) {
      parts.add(r.Contact__r.Phone);
    } else if (String.isNotBlank(r.Contact__r?.MobilePhone)) {
      parts.add(r.Contact__r.MobilePhone);
    }
    if (String.isNotBlank(r.Contact__r?.Email)) {
      parts.add(r.Contact__r.Email);
    }
    return parts.isEmpty() ? null : String.join(parts, ' · ');
  }

  private static String designerEmail(Feedback_Response__c r) {
    User d = r.Booking__r?.TravelDesigner__r;
    return d != null &&
      d.IsActive == true &&
      String.isNotBlank(d.Email)
      ? d.Email
      : null;
  }

  private static String designerNote(Feedback_Response__c r) {
    String name = r.Booking__r?.TravelDesigner__r?.Name;
    return String.isBlank(name) ? '' : ' (' + name + ')';
  }

  private static String score(Decimal value) {
    return value == null ? '–' : String.valueOf(value.intValue());
  }

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
