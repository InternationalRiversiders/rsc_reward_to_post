import Component from "@glimmer/component";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";
import { themePrefix } from "virtual:theme";
import { rewardPost } from "../lib/rsc_api";
import RewardModal from "./reward-modal";

export default class RewardButton extends Component {
  @service modal;

  @action
  reward() {
    this.modal.show(RewardModal, {
      model: {
        post: this.args.post,
        title: i18n(themePrefix("reward_modal.title")),
        confirmLabel: i18n(themePrefix("reward_modal.confirm")),
        cancelLabel: i18n(themePrefix("reward_modal.cancel")),
        rewardPost: (params) => rewardPost(params),
      },
    });
  }

  <template>
    <DButton
      class="post-action-menu__reward"
      ...attributes
      @action={{this.reward}}
      @icon="reward_icon"
      @title={{themePrefix "reward_to_post.title"}}
    />
  </template>
}
