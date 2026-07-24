import { ajax } from "discourse/lib/ajax";

const API_PREFIX = "/app-rsc-api";
const MAX_RETRIES = 3;
const TIMEOUT_MS = 10_000;
const TOKEN_BUFFER_MS = 5_000; // token 过期前 5 秒就视为过期，避免边界

// =============================================================================
// Token 管理
// =============================================================================
//
// 懒加载 + 内存缓存 + 并发去重 + 401 自动刷新

let tokenCache = null;   // { value: string, expiresAt: number } | null
let tokenPromise = null; // Promise<string> | null

async function getAuthToken() {
  if (tokenCache && Date.now() < tokenCache.expiresAt - TOKEN_BUFFER_MS) {
    return tokenCache.value;
  }

  if (!tokenPromise) {
    tokenPromise = exchangeToken();
  }

  try {
    return await tokenPromise;
  } finally {
    tokenPromise = null;
  }
}

async function exchangeToken() {
  const doExchange = () =>
    withTimeout(
      ajax(`${API_PREFIX}/auth/session-exchange`, {
        type: "POST",
        contentType: "application/json",
        data: JSON.stringify({}),
        credentials: "include",
      }),
      TIMEOUT_MS
    );

  let lastErr;
  for (let attempt = 0; attempt <= 1; attempt++) {
    try {
      const response = await doExchange();
      tokenCache = {
        value: response.token,
        expiresAt: new Date(response.expiresAt).getTime(),
      };
      return tokenCache.value;
    } catch (err) {
      lastErr = err;
    }
  }
  throw lastErr;
}

function clearTokenCache() {
  tokenCache = null;
  tokenPromise = null;
}

// =============================================================================
// 带认证的请求
// =============================================================================

/**
 * 发起带 RSC JWT 认证的 API 请求。
 * token 自动获取/缓存；401 时自动清缓存重试一次。
 */
export async function authRequest(url, opts = {}) {
  const doRequest = () =>
    getAuthToken().then((token) =>
      withTimeout(
        ajax(url, {
          ...opts,
          headers: {
            ...opts.headers,
            Authorization: `Bearer ${token}`,
          },
        }),
        TIMEOUT_MS
      )
    );

  try {
    return await doRequest();
  } catch (err) {
    if (err.status === 401) {
      clearTokenCache();
      return await doRequest();
    }
    throw err;
  }
}

// =============================================================================
// Tips 缓存
// =============================================================================

/** @type {Map<number, {status: string, promise: Promise<void>|null, tipsByPostNumber: Map<number, object[]>|null, error: Error|null, retryCount: number}>} */
const tipsCache = new Map();

function ensureEntry(topicId) {
  if (!tipsCache.has(topicId)) {
    tipsCache.set(topicId, {
      status: "loading",
      promise: null,
      tipsByPostNumber: null,
      error: null,
      retryCount: 0,
    });
  }
  return tipsCache.get(topicId);
}

function withTimeout(promise, ms) {
  return Promise.race([
    promise,
    new Promise((_, reject) =>
      setTimeout(() => reject(new Error(`Request timed out after ${ms}ms`)), ms)
    ),
  ]);
}

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

      if (entry.retryCount >= MAX_RETRIES) {
        entry.status = "error";
        entry.error = err;
        entry.promise = null;
        throw err;
      }

      await new Promise((r) => setTimeout(r, 1000 * entry.retryCount));
    }
  }
}

// =============================================================================
// Public API
// =============================================================================

/** 获取某个帖子的打赏列表（无需认证） */
export async function fetchPostTips(topicId, postNumber) {
  const entry = ensureEntry(topicId);

  if (entry.status === "loaded") {
    return entry.tipsByPostNumber?.get(postNumber) ?? [];
  }

  if (entry.status === "error") {
    throw entry.error;
  }

  if (!entry.promise) {
    entry.promise = fetchTipsForTopic(topicId);
  }

  await entry.promise;

  if (entry.status === "loaded") {
    return entry.tipsByPostNumber?.get(postNumber) ?? [];
  }

  throw entry.error ?? new Error("Unknown fetch error");
}

/** 清空 tips 缓存 */
export function clearRewardsCache() {
  tipsCache.clear();
}

/**
 * 为帖子打赏（需要认证）。
 *
 * @param {object} params
 * @param {number} params.toDiscourseUserId
 * @param {string} params.toUsername
 * @param {string} params.amount
 * @param {number} params.topicId
 * @param {number} params.postId
 * @param {number} params.postNumber
 * @returns {Promise<object>} 新创建的 Tip
 */
export async function rewardPost({
  toDiscourseUserId,
  toUsername,
  amount,
  topicId,
  postId,
  postNumber,
}) {
  const result = await authRequest(`${API_PREFIX}/wallet/post-tips`, {
    type: "POST",
    contentType: "application/json",
    data: JSON.stringify({
      toDiscourseUserId,
      toUsername,
      amount,
      topicId,
      postId,
      postNumber,
    }),
  });

  // 清除该 topic 的缓存，下次 fetchPostTips 会重新拉取
  tipsCache.delete(topicId);

  // 通知 RewardPostInfo 组件刷新
  document.dispatchEvent(
    new CustomEvent("reward:updated", { detail: { topicId } })
  );

  return result.tip;
}
