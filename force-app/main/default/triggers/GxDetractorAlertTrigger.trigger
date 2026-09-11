/**
 * Sends the detractor alerts raised by survey submissions. Runs as the
 * Automated Process user, outside the guest user's restricted context.
 */
trigger GxDetractorAlertTrigger on Gx_Detractor_Alert__e(after insert) {
  GxDetractorAlert.send(Trigger.new);
}
