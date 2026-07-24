import Component from "@glimmer/component";
import { action } from "@ember/object";
import DButton from "discourse/ui-kit/d-button";

export default class RewardButton extends Component {
  @action
  reward() {
    // 空函数，后续实现打赏逻辑
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
