import { LightningElement, api } from "lwc";
import { PAGE_SIZE, rangeLabel } from "c/gxDashboardView";

/**
 * gxPager
 *
 * "11–20 of 57  ‹ Page 2 of 6 ›" under a dashboard list. Stateless: the list
 * owner holds the page and listens for `pagechange`. Shows nothing while the
 * whole list fits on one page.
 */
export default class GxPager extends LightningElement {
  @api total = 0;
  @api page = 1;
  @api pageSize = PAGE_SIZE;
  /** What is being paged, for screen readers: "Follow-up pages". */
  @api label = "Pages";

  get pages() {
    return Math.max(1, Math.ceil((this.total || 0) / this.pageSize));
  }

  get visible() {
    return (this.total || 0) > this.pageSize;
  }

  get range() {
    return rangeLabel(this.page, this.total, this.pageSize);
  }

  get pageText() {
    return `Page ${this.page} of ${this.pages}`;
  }

  get atStart() {
    return this.page <= 1;
  }

  get atEnd() {
    return this.page >= this.pages;
  }

  handlePrevious() {
    this.go(this.page - 1);
  }

  handleNext() {
    this.go(this.page + 1);
  }

  go(page) {
    if (page < 1 || page > this.pages || page === this.page) {
      return;
    }
    this.dispatchEvent(new CustomEvent("pagechange", { detail: { page } }));
  }
}
