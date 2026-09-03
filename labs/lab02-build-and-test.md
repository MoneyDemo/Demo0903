# Lab 02 — Build & Test（Maven Wrapper + Job Summary）

## 學習目標

做完這個 lab，你應該可以：

- 使用 `actions/checkout@v5` 把原始碼抓到 runner 上，並說明為什麼一定要這一步
- 使用 `actions/setup-java@v6` 安裝指定的 JDK（temurin、Java 21）
- 在 workflow 中用 Maven Wrapper 執行 `./mvnw -B verify` 完成 build + test
- 在 workflow 最上層加上最小權限的 `permissions:`
- 用 `$GITHUB_STEP_SUMMARY` 產生一份人看得懂的執行摘要
- 在 log 中找到測試結果與失敗訊息

## 對應模組

**Module 1 — Design and Manage Workflows**（jobs / steps、使用 actions）
**Module 2 — Consume and Troubleshoot Workflows**（讀 log、job summary）

## 前置需求

- 已完成 [Lab 01](lab01-first-workflow.md)
- repo 根目錄有 `pom.xml` 與 Maven Wrapper（`mvnw`、`mvnw.cmd`、`.mvn/wrapper/`）
- 本機**不需要**安裝 Maven；如果你想在本機先試跑：
  - Windows：`.\mvnw.cmd -B verify`
  - Linux / macOS：`./mvnw -B verify`
- 本機需要 JDK 21（`java -version` 顯示 21）

## 步驟

1. 建立 `.github/workflows/lab02-build.yml`，從 [`starters/lab02.yml`](starters/lab02.yml) 開始。

2. **加上最小權限。** 在 `on:` 之後、`jobs:` 之前加入一個 workflow 層級的 `permissions:` 區塊。這個 workflow 只需要讀原始碼，所以只給 `contents: read`。
   > 為什麼要寫？因為只要明確宣告 `permissions:`，**沒有列出來的權限一律變成 none**。這是 Module 5「最小權限」的第一步，養成習慣。

3. **Checkout。** 第一個 step 使用 `actions/checkout@v5`。runner 每次都是一台全新的空機器，**不會**自動有你的程式碼。少了這一步，後面 `./mvnw` 一定會失敗（Lab 06 會讓你親眼看到）。

4. **安裝 JDK。** 使用 `actions/setup-java@v6`，在 `with:` 底下指定：
   - `distribution:` → `temurin`
   - `java-version:` → `'21'`（**加引號**。不加引號時 YAML 會把它讀成數字，雖然多數情況仍可運作，但寫成字串最保險，遇到 `1.8`、`11.0` 這類版本尤其重要）

5. **讓 mvnw 可執行。** Linux runner 上 `mvnw` 可能沒有執行權限，加一個 step 執行 `chmod +x ./mvnw`。
   > 小技巧：如果你在本機用 `git update-index --chmod=+x mvnw` 把執行權限存進 git，就不需要這一步。但課堂上直接加 `chmod` 最單純。

6. **Build + Test。** 執行 `./mvnw -B verify`。
   - `-B`（batch mode）關閉互動與顏色輸出，讓 CI log 乾淨可讀
   - `verify` 會跑完 compile → test → package，並產出 **`target/simpleweb.jar`**

7. **寫 Job Summary。** 最後一個 step 把 Markdown 內容 append 到 `$GITHUB_STEP_SUMMARY` 這個**檔案路徑**（它是環境變數，不是指令）。例如：
   ```bash
   echo "## Build 結果" >> "$GITHUB_STEP_SUMMARY"
   ```
   摘要至少要包含：commit SHA、branch、以及 `target/simpleweb.jar` 是否存在。
   加上 `if: always()`，這樣即使 build 失敗，摘要仍會產生——這在除錯時非常有用。

8. **Push 並觀察。** 到 Actions 看這次 run：
   - run 的**總覽頁最上方**會顯示你寫的 Summary（Markdown 會被渲染）
   - 展開 `Build and test` step，往下捲找 `BUILD SUCCESS` 或 `Tests run: ...`

9. **（建議）故意讓測試失敗一次。** 隨便改壞一個測試的斷言，push，然後在 log 中找出：
   - 哪一個 step 變紅
   - `Tests run: x, Failures: y` 這一行
   - 失敗測試的類別名稱與行號

   看完再改回來。這個經驗比看十頁投影片有用。

## 你要自己完成的 YAML

Starter：[`starters/lab02.yml`](starters/lab02.yml)

```yaml
name: Lab02 Build and Test

on:
  push:
    branches: [ main ]
  workflow_dispatch:

# TODO 1: workflow 層級最小權限（只需要讀取原始碼）

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      # TODO 2: actions/checkout@v5
      # TODO 3: actions/setup-java@v6（temurin / '21'）
      # TODO 4: chmod +x ./mvnw
      # TODO 5: ./mvnw -B verify
      # TODO 6: 把摘要寫進 $GITHUB_STEP_SUMMARY（記得 if: always()）
```

## 驗收標準

- [ ] Actions 頁面該 run 顯示**綠色勾勾**
- [ ] `Build and test` step 的 log 中可以找到 `BUILD SUCCESS`
- [ ] log 中可以找到 `Tests run:` 開頭的測試統計
- [ ] run 的總覽頁上方顯示你寫的 Summary，且其中的 commit SHA 是實際值
- [ ] Summary 顯示 `target/simpleweb.jar` 存在（有勾勾與檔案大小）
- [ ] 你能指著 log 說出：JDK 是在哪一個 step 被裝好的

## 常見錯誤

| 症狀 | 原因 | 修法 |
|---|---|---|
| `./mvnw: No such file or directory` | 少了 `actions/checkout` | 在最前面加上 checkout step |
| `Permission denied: ./mvnw` | Linux 上 mvnw 沒有執行權限 | 加 `chmod +x ./mvnw` |
| `release version 21 not supported` | JDK 版本不對或 setup-java 沒生效 | 確認 `java-version: '21'` 且 setup-java 在 build 之前 |
| `unable to find valid certification path` / 下載相依套件失敗 | 網路或 proxy 問題 | 重跑一次；持續失敗請告知講師 |
| Summary 是空的 | 寫成 `>` 覆蓋、或漏了 `$` | 用 `>>` append，且變數要寫 `"$GITHUB_STEP_SUMMARY"` |
| Summary 只在成功時出現 | 沒加 `if: always()` | 在該 step 加上 `if: always()` |
| `java-version: 21` 被解讀成奇怪的值 | YAML 型別轉換 | 一律寫成 `'21'` |

## 解答

[`solutions/lab02.yml`](solutions/lab02.yml)
