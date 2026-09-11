import { LightningElement, api } from "lwc";

/**
 * gxVenueBoard
 *
 * One leaderboard: ranked venues first, then the ones without enough ratings
 * to rank yet. Stateless - the dashboard passes an already-shaped board from
 * gxDashboardView.venueList and listens for `select` to open the drill-down.
 */
export default class GxVenueBoard extends LightningElement {
  @api title;
  @api board;
  @api minRatings;

  get ranked() {
    return (this.board && this.board.ranked) || [];
  }

  get unranked() {
    return (this.board && this.board.unranked) || [];
  }

  get hasRanked() {
    return this.ranked.length > 0;
  }

  get hasUnranked() {
    return this.unranked.length > 0;
  }

  get isEmpty() {
    return !this.hasRanked && !this.hasUnranked;
  }

  /** Only when nothing is ranked yet, but some venues are waiting. */
  get showRankingNote() {
    return !this.hasRanked && this.hasUnranked;
  }

  get rankingNote() {
    return `None with ${this.minRatings} or more ratings yet.`;
  }

  handleSelect(event) {
    const { name, category } = event.currentTarget.dataset;
    this.dispatchEvent(
      new CustomEvent("select", { detail: { name, category } })
    );
  }
}
