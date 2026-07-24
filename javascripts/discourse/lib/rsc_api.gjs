import { ajax } from "discourse/lib/ajax";

const API_PREFIX = "/app-rsc-api";
const MAX_RETRIES = 3;
const TIMEOUT_MS = 10_000;

// =============================================================================
// Cache
// =============================================================================
//
// 结构: Map<topicId, CacheEntry>
//
// CacheEntry:
//   {
//     status:   "loading" | "loaded" | "error",
//     promise:  Promise<void> | null,           // 进行中的请求，null 表示无事发生/已完成/已失败
//     tipsByPostNumber: Map<number, Tip[]>,    // postNumber → Tip[]
//     error:    Error | null,
//     retryCount: number,
//   }
//
// 生命周期:
//   1. 组件调用 fetchPostTips(topicId, postNumber)
//   2. 如果该 topic 已 loaded  → 直接从 tipsByPostNumber 取值返回
//   3. 如果该 topic 正 loading → await 同一个 promise，不重复请求
//   4. 如果该 topic 已 error   → 直接 throw（组件自行决定是否展示错误状态）
//   5. 都没有                   → 创建 CacheEntry，发起请求
//   6. 用户离开 topic / 刷新页面 → 模块重新初始化，Map 自然清空
//
// Tip（API 返回的单条打赏记录）:
//   {
//     id, topicId, postId, postNumber,
//     fromDiscourseUserId, fromUsername,
//     toDiscourseUserId,   toUsername,
//     amountRsc, createdAt
//   }

/** @type {Map<number, {status: string, promise: Promise<void>|null, tipsByPostNumber: Map<number, object[]>|null, error: Error|null, retryCount: number}>} */
const cache = new Map();

function ensureEntry(topicId) {
  if (!cache.has(topicId)) {
    cache.set(topicId, {
      status: "loading", // 初始就是 loading，因为创建即准备请求
      promise: null,
      tipsByPostNumber: null,
      error: null,
      retryCount: 0,
    });
  }
  return cache.get(topicId);
}

// =============================================================================
// Helpers
// =============================================================================

/**
 * 给 Promise 加超时——不真正 abort 底层请求，但从调用方视角 10s 后 reject
 */
function withTimeout(promise, ms) {
  return Promise.race([
    promise,
    new Promise((_, reject) =>
      setTimeout(() => reject(new Error(`Request timed out after ${ms}ms`)), ms)
    ),
  ]);
}

/**
 * 将 API 返回的 tips 数组转换为 postNumber → Tip[] 的 Map
 */
function indexTips(tips) {
  const map = new Map();
  for (const tip of tips) {
    const key = tip.postNumber;
    if (!map.has(key)) {
      map.set(key, []);
    }
    map.get(key).push(tip);
  }
  return map;
}

// =============================================================================
// Internal fetch — 包含重试逻辑
// =============================================================================

async function fetchTipsForTopic(topicId) {
  const entry = ensureEntry(topicId);

  for (let attempt = 0; attempt < MAX_RETRIES; attempt++) {
    try {
      const result = await withTimeout(
        ajax(`${API_PREFIX}/wallet/post-tips?topicId=${topicId}`),
        TIMEOUT_MS
      );

      entry.status = "loaded";
      entry.tipsByPostNumber = indexTips(result.tips);
      entry.error = null;
      entry.promise = null;
      return;
    } catch (err) {
      entry.retryCount = attempt + 1;

      // 最后一次重试也失败 → 标记 error
      if (entry.retryCount >= MAX_RETRIES) {
        entry.status = "error";
        entry.error = err;
        entry.promise = null;
        throw err;
      }

      // 指数退避：1s → 2s
      await new Promise((r) => setTimeout(r, 1000 * entry.retryCount));
    }
  }
}

// =============================================================================
// Public API
// =============================================================================

/**
 * 获取某个帖子收到的打赏列表。
 *
 * @param {number} topicId  - 帖子所属 topic 的 ID
 * @param {number} postNumber - 帖子的 postNumber（同 topic 内唯一）
 * @returns {Promise<object[]>} 该帖子收到的所有 Tip 数组；帖子没有打赏时返回 []
 */
export async function fetchPostTips(topicId, postNumber) {
  const entry = ensureEntry(topicId);

  // 已加载 → 直接查
  if (entry.status === "loaded") {
    return entry.tipsByPostNumber?.get(postNumber) ?? [];
  }

  // 已失败 → 不重试，直接抛
  if (entry.status === "error") {
    throw entry.error;
  }

  // status === "loading"
  // 如果没有正在进行的请求，发起一个
  if (!entry.promise) {
    entry.promise = fetchTipsForTopic(topicId);
  }

  // 同一 topic 的所有并发调用都 await 同一个 promise
  await entry.promise;

  if (entry.status === "loaded") {
    return entry.tipsByPostNumber?.get(postNumber) ?? [];
  }

  // promise 完成后仍然是 error（理论上 fetchTipsForTopic 会 throw，不太会走到这里）
  throw entry.error ?? new Error("Unknown fetch error");
}

/**
 * 清空所有缓存——在用户离开 topic 时调用，确保再次进入时重新拉取。
 */
export function clearRewardsCache() {
  cache.clear();
}

/**
 * 为帖子打赏
 * TODO: 后续实现
 */
export async function rewardPost(postId) {
  // const response = await ajax(`${API_PREFIX}/reward/${postId}`, { type: "POST" });
  // return response;
}
