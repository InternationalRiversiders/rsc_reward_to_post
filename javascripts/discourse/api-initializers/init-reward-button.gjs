import { apiInitializer } from "discourse/lib/api";
import InjectRewardSprite from "../components/inject-reward-sprite";
import RewardPostInfo from "../components/reward-post-info";
import RewardButton from "../components/reward-button";

export default apiInitializer((api) => {
  // 将原始 SVG 注入到 div#svg-sprites 的 div.reward 中
  api.renderInOutlet("below-site-header", InjectRewardSprite);

  // cooked 和 post-menu 之间插入内容
  api.renderAfterWrapperOutlet("post-content-cooked-html", RewardPostInfo);

  // 在「更多」展开区注册按钮
  api.registerValueTransformer(
    "post-menu-buttons",
    ({ value: dag, context: { collapsedButtons } }) => {
      dag.add("reward", RewardButton, {
        after: "showMore",
      });

      collapsedButtons.hide("reward");
    }
  );
});
