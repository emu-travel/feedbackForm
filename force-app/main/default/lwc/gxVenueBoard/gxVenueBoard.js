import { LightningElement, api } from "lwc";
import { pageOf } from "c/gxDashboardView";

/**
 * gxVenueBoard
 *
 * One leaderboard: ranked venues first, then the ones without enough ratings
 * to rank yet. The dashboard passes an already-shaped board from
 * gxDashboardView.venueList and listens for `select` to open the drill-down.
 * Each of the two lists pages ten venues at a time.
 */
export default class GxVenueBoard extends LightningElement {
  @api title;
  @api minRatings;

  rankedPageNo = 1;
  unrankedPageNo = 1;
  _board;

  /** A new board (a filter changed) starts both lists on page 1 again. */
  @api
  get board() {
    return this._board;
  }
  set board(value) {
    this._board = value;
    this.rankedPageNo = 1;
    this.unrankedPageNo = 1;
  }

  get ranked() {
    return (this._board && this._board.ranked) || [];
  }

  get unranked() {
    return (this._board && this._board.unranked) || [];
  }

  get rankedPage() {
    return pageOf(this.ranked, this.rankedPageNo);
  }

  get unrankedPage() {
    return pageOf(this.unranked, this.unrankedPageNo);
  }

  handleRankedPage(event) {
    this.rankedPageNo = event.detail.page;
  }

  handleUnrankedPage(event) {
    this.unrankedPageNo = event.detail.page;
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
