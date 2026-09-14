import { LightningElement, api } from "lwc";

/**
 * gxServiceIcon
 *
 * The small icon tile at the top of every card in the survey - flight,
 * transfer, rental car, hotel, golf course - so each thing a guest rates is
 * recognisable at a glance and every step looks the same.
 *
 * Decorative only: the card's label and name say what it is.
 */
export default class GxServiceIcon extends LightningElement {
  /** flight | transfer | car | hotel | golf */
  @api name;

  get isFlight() {
    return this.name === "flight";
  }
  get isTransfer() {
    return this.name === "transfer";
  }
  get isCar() {
    return this.name === "car";
  }
  get isHotel() {
    return this.name === "hotel";
  }
  get isGolf() {
    return this.name === "golf";
  }
}
