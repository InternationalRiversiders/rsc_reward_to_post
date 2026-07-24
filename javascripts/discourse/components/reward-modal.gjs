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
    // 拼接完整 i18n key，形如 "theme_translations.N.reward_modal.error.XXX"
    const key = themePrefix(`reward_modal.error.${this.error}`);
    const msg = i18n(key);
    // 刻意设计：已知错误码走 i18n 翻译；未知错误码原样显示字符串。
    // 这样后端新增错误码时，前端即使未及时更新 locale 文件，用户也能看到有意义的
    // 错误标识（而非模糊的"服务端异常"），便于用户反馈问题时提供准确信息。
    //
    // Discourse i18n 缺失翻译时返回 "[locale.theme_translations.N...]" 格式的
    // 占位符（truthy），而真实翻译不会是这种格式。通过首字符 "[" 来区分二者。
    if (msg && !msg.startsWith("[")) {
      return msg;
    }
    return this.error;
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
      const resp = err.jqXHR?.responseJSON;

      // 按优先级尝试多种常见的错误响应格式，提取字符串类型的错误信息
      let rawError = err.rscErrorCode;

      if (!rawError && resp) {
        rawError =
          // 1. error 本身是字符串："error": "CODE"
          (typeof resp.error === "string" && resp.error) ||
          // 2. 嵌套的 code 优先于 message，便于走 i18n 或原样反馈
          (typeof resp.error?.code === "string" && resp.error.code) ||
          // 3. 嵌套的 message
          (typeof resp.error?.message === "string" && resp.error.message) ||
          // 4. Rails 默认复数格式："errors": ["msg1", ...]
          (Array.isArray(resp.errors) && typeof resp.errors[0] === "string" && resp.errors[0]) ||
          // 5. 顶层 message 字段
          (typeof resp.message === "string" && resp.message);
      }

      this.error = typeof rawError === "string" ? rawError : "INTERNAL_SERVER_ERROR";
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
