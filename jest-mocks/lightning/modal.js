/*
 * Test stand-in for lightning/modal, which sfdx-lwc-jest does not stub.
 * A modal built on it renders like any component. `open` resolves at once
 * for tests to spy on; `close` fires a `modalclose` event with its result.
 */
import { LightningElement, api } from "lwc";

export default class LightningModal extends LightningElement {
  @api label;
  @api size;
  @api description;
  @api disableClose;

  static open() {
    return Promise.resolve();
  }

  /** Announced as a `modalclose` event, since tests cannot spy on it. */
  close(result) {
    this.dispatchEvent(new CustomEvent("modalclose", { detail: result }));
  }
}
