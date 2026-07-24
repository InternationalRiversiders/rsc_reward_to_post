import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import DButton from "discourse/ui-kit/d-button";
import DModal from "discourse/ui-kit/d-modal";
import { i18n } from "discourse-i18n";
import { themePrefix } from "virtual:theme";

export default class RewardModal extends Component {
  @tracked amount = "1";
  @tracked loading = false;
  @tracked error = null;

  constructor() {
    super(...arguments);
    document.body.classList.add("reward-modal-open");
  }

  willDestroy() {
    super.willDestroy();
    document.body.classList.remove("reward-modal-open");
  }

  get confirmDisabled() {
    return this.loading || !(Number(this.amount) > 0);
  }

  get errorMessage() {
    if (!this.error) {
      return null;
    }
    const msg = i18n(themePrefix(`reward_modal.error.${this.error}`));
    // 刻意设计：有对应翻译就用翻译，没有则原样显示错误码字符串。
    // 这样后端新增错误码时，前端即使未及时更新 locale 文件，用户也能看到有意义的
    // 错误标识（而非模糊的"服务端异常"），便于用户反馈问题时提供准确信息。
    return msg ? msg : this.error;
  }

  @action
  updateAmount(e) {
    let val = e.target.value.replace(/[^0-9.]/g, "");
    const dotIndex = val.indexOf(".");
    if (dotIndex !== -1) {
      val = val.slice(0, dotIndex + 1) + val.slice(dotIndex + 1).replace(/\./g, "");
    }
    if (val.includes(".")) {
      val = val.slice(0, val.indexOf(".") + 3);
    }
    if (val.startsWith("0") && val.length > 1 && val[1] !== ".") {
      val = val.slice(1);
    }
    this.amount = val;
  }

  @action
  cancel() {
    this.args.closeModal();
  }

  @action
  async confirm() {
    if (!this.amount) {
      return;
    }

    const post = this.args.model.post;
    this.loading = true;
    this.error = null;

    try {
      await this.args.model.rewardPost({
        toDiscourseUserId: post.user_id,
        toUsername: post.username,
        amount: this.amount,
        topicId: post.topic_id,
        postId: post.id,
        postNumber: post.post_number,
      });
      this.args.closeModal();
    } catch (err) {
      this.error = err.rscErrorCode || err.jqXHR?.responseJSON?.error || "INTERNAL_SERVER_ERROR";
    } finally {
      this.loading = false;
    }
  }

  <template>
    <DModal
      class="reward-modal"
      @closeModal={{@closeModal}}
      @title={{@model.title}}
    >
      <:body>
        <p class="reward-modal__recipient">
          {{@model.title}}
          <a
            href="/u/{{@model.post.username}}"
            data-user-card={{@model.post.username}}
          >{{@model.post.username}}</a>
        </p>
        <div class="reward-modal__input-row">
          <input
            type="text"
            inputmode="numeric"
            class="reward-modal__amount-input"
            value={{this.amount}}
            placeholder="1"
            {{on "input" this.updateAmount}}
          />
          <span class="reward-modal__unit">RSC</span>
        </div>
        {{#if this.errorMessage}}
          <div class="reward-modal__error">{{this.errorMessage}}</div>
        {{/if}}
      </:body>
      <:footer>
        <DButton
          class="btn-default reward-modal__cancel"
          @translatedLabel={{@model.cancelLabel}}
          @action={{this.cancel}}
        />
        <DButton
          class="btn-primary reward-modal__confirm"
          @translatedLabel={{@model.confirmLabel}}
          @action={{this.confirm}}
          @disabled={{this.confirmDisabled}}
        />
      </:footer>
    </DModal>
  </template>
}
