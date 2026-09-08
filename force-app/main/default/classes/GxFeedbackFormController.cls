/**
 * GxFeedbackFormController
 *
 * The only Apex the guest user on the public feedback site can call.
 * Thin wrapper: no logic here, everything is in GxFeedbackService.
 * Grant the guest profile access to THIS class only.
 *
 * Errors are deliberately swallowed into a neutral response so the public form
 * never leaks a stack trace or reveals whether a booking number exists.
 */
public with sharing class GxFeedbackFormController {
  /** Test hook: makes both methods throw so the catch paths are covered. Never set outside tests. */
  @TestVisible
  private static Boolean throwForTest = false;

  @AuraEnabled(cacheable=true)
  public static GxFeedbackService.Context getContext(
    String bookingNumber,
    String secret
  ) {
    try {
      if (throwForTest) {
        throw new GxFeedbackService.FormException('test');
      }
      return GxFeedbackService.getContext(bookingNumber, secret);
    } catch (Exception e) {
      GxFeedbackService.Context c = new GxFeedbackService.Context();
      c.ok = false;
      c.message = 'invalid';
      return c;
    }
  }

  @AuraEnabled
  public static GxFeedbackService.SubmitResult submit(String payloadJson) {
    try {
      if (throwForTest) {
        throw new GxFeedbackService.FormException('test');
      }
      return GxFeedbackService.submit(payloadJson);
    } catch (Exception e) {
      GxFeedbackService.SubmitResult r = new GxFeedbackService.SubmitResult();
      r.ok = false;
      r.message = 'Ihr Feedback konnte nicht verarbeitet werden.';
      return r;
    }
  }
}
