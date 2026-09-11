import { api } from "lwc";
import LightningModal from "lightning/modal";
import getResponseDetail from "@salesforce/apex/GxFeedbackDashboardController.getResponseDetail";
import { responseView } from "c/gxDashboardView";

/**
 * gxResponseModal
 *
 * One guest's whole answer, opened from anywhere on the dashboard that shows
 * a response. Laid out screen by screen as the guest filled it in.
 *
 * Opened with GxResponseModal.open({ responseId, size, label }). Resolves
 * with { navigate: recordId } when the user asks to open the booking or the
 * response record - the dashboard does the navigating, after this closes.
 */
export default class GxResponseModal extends LightningModal {
  @api responseId;

  view;
  error;
  loading = true;

  async connectedCallback() {
    try {
      const detail = await getResponseDetail({ responseId: this.responseId });
      this.view = responseView(detail);
    } catch (e) {
      this.error =
        (e && e.body && e.body.message) || "This feedback could not be loaded.";
    } finally {
      this.loading = false;
    }
  }

  get heading() {
    return this.view ? this.view.title : "Feedback response";
  }

  get hasBooking() {
    return Boolean(this.view && this.view.bookingId);
  }

  get noRecord() {
    return !this.view;
  }

  handleOpenBooking() {
    this.close({ navigate: this.view.bookingId });
  }

  handleOpenRecord() {
    this.close({ navigate: this.view.responseId });
  }

  handleClose() {
    this.close();
  }
}
