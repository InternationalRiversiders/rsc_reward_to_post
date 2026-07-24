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
        {{#if @showCount}}
          <span class="reward-post-info__count">×{{@tipCount}}</span>
        {{/if}}
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
    return this.tips.reduce((sum, tip) => sum + (tip.tipCount || 1), 0) >= 3;
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

  get scrollable() {
    return this.tips.length > 10;
  }

  get formattedTips() {
    return this.tips.map((tip) => ({
      ...tip,
      showCount: (tip.tipCount || 1) > 1,
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

  // 刻意设计：加载打赏列表失败时静默降级为空数组，不打断用户的正常浏览体验。
  // 打赏展示属于辅助信息，加载失败不应阻塞页面其他功能。
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
        <div class="reward-post-info__list {{if this.scrollable "reward-post-info__list--scrollable"}}">
          {{#each this.formattedTips as |tip|}}
            <TipRow
              @username={{tip.fromUsername}}
              @amount={{tip.amountRsc}}
              @unit={{this.rscUnit}}
              @formattedTime={{tip.formattedTime}}
              @showCount={{tip.showCount}}
              @tipCount={{tip.tipCount}}
            />
          {{/each}}
        </div>
      </div>
    {{/if}}
  </template>
}
