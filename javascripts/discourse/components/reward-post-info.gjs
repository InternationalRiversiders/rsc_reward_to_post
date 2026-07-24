import Component from "@glimmer/component";
import { service } from "@ember/service";
import { tracked } from "@glimmer/tracking";
import { i18n } from "discourse-i18n";
import { themePrefix } from "virtual:theme";
import moment from "moment";
import { fetchPostTips } from "../lib/rsc_api";

const RewardIcon = <template>
  <svg
    class="fa d-icon d-icon-reward_icon svg-icon svg-node reward-post-info__icon"
    aria-hidden="true"
  >
    <use href="#reward_icon"></use>
  </svg>
</template>;

const TipRow = <template>
  <div class="reward-post-info__item {{if @total "reward-post-info__item--total"}}">
    <span class="reward-post-info__left">
      <RewardIcon />
      {{#if @total}}
        <span class="reward-post-info__user">{{@username}}</span>
      {{else}}
        <a
          href="/u/{{@username}}"
          data-user-card={{@username}}
          class="reward-post-info__user"
          title={{@formattedTime}}
        >{{@username}}</a>
      {{/if}}
    </span>
    <span class="reward-post-info__amount">{{@amount}} {{@unit}}</span>
  </div>
</template>;

export default class RewardPostInfo extends Component {
  @service router;

  @tracked tips = [];

  get isTopicPage() {
    return this.router.currentRouteName?.startsWith("topic.");
  }

  get showTotal() {
    return this.tips.length >= 3;
  }

  get totalRsc() {
    const totalCents = this.tips.reduce(
      (sum, t) => sum + Math.round(Number(t.amountRsc || 0) * 100),
      0
    );
    return (totalCents / 100).toFixed(2).replace(/\.?0+$/, "");
  }

  get totalLabel() {
    return i18n(themePrefix("reward_post_info.total"));
  }

  get rscUnit() {
    return i18n(themePrefix("reward_post_info.rsc_unit"));
  }

  get formattedTips() {
    return this.tips.map((tip) => ({
      ...tip,
      formattedTime: moment(tip.createdAt).format("YYYY-MM-DD HH:mm:ss"),
    }));
  }

  constructor() {
    super(...arguments);
    if (!this.isTopicPage) {
      return;
    }

    const post = this.args.post;
    this._topicId = post.topic_id;
    this.loadTips();

    this._onRewardUpdated = (e) => {
      if (e.detail.topicId === this._topicId) {
        this.loadTips();
      }
    };
    document.addEventListener("reward:updated", this._onRewardUpdated);
  }

  willDestroy() {
    super.willDestroy();
    if (this._onRewardUpdated) {
      document.removeEventListener("reward:updated", this._onRewardUpdated);
    }
  }

  async loadTips() {
    try {
      this.tips = await fetchPostTips(this._topicId, this.args.post.post_number);
    } catch {
      this.tips = [];
    }
  }

  <template>
    {{#if this.tips.length}}
      <div class="reward-post-info">
        {{#if this.showTotal}}
          <TipRow
            @total={{true}}
            @username={{this.totalLabel}}
            @amount={{this.totalRsc}}
            @unit={{this.rscUnit}}
          />
        {{/if}}
        {{#each this.formattedTips as |tip|}}
          <TipRow
            @username={{tip.fromUsername}}
            @amount={{tip.amountRsc}}
            @unit={{this.rscUnit}}
            @formattedTime={{tip.formattedTime}}
          />
        {{/each}}
      </div>
    {{/if}}
  </template>
}
