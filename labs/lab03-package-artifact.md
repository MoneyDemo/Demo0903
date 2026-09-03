# Lab 03 — 拆成兩個 job，用 artifact 交接 jar

## 學習目標

做完這個 lab，你應該可以：

- 在一份 workflow 中定義多個 job，並用 `needs:` 建立執行順序
- 說明「每個 job 跑在不同的 runner、檔案不共用」這個關鍵事實
- 使用 `actions/upload-artifact@v7` 上傳建置產出
- 使用 `actions/download-artifact@v7` 在下游 job 取回同一個檔案
- **在概念上**分辨 artifact 與 cache 的差別，並說出各自的使用時機

## 對應模組

**Module 1 — Design and Manage Workflows**（jobs 相依關係、artifacts）

## 前置需求

- 已完成 [Lab 02](lab02-build-and-test.md)，`./mvnw -B verify` 可以成功產出 `target/simpleweb.jar`

## 步驟

1. 建立 `.github/workflows/lab03-artifact.yml`，從 [`starters/lab03.yml`](starters/lab03.yml) 開始。starter 已經幫你把 `build` job 寫好了（就是 Lab 02 的內容），你要補的是 artifact 的上傳／下載與 job 相依。

2. **先理解為什麼需要 artifact。** 這一點請務必想清楚：

   > 同一份 workflow 裡的每一個 job，預設都是在**各自獨立的全新 runner**上執行。
   > `build` job 產生的 `target/simpleweb.jar`，在 `package` job 的機器上**根本不存在**。

   要把檔案從一個 job 交給另一個 job，就得經過 GitHub 的 artifact 儲存體：上傳 → 下載。

3. **上傳 artifact。** 在 `build` job 的最後加一個 step，使用 `actions/upload-artifact@v7`：
   - `name:` — artifact 的名稱，建議 `simpleweb-jar`
   - `path:` — 要上傳的檔案，`target/simpleweb.jar`
   - `if-no-files-found: error` — **強烈建議加上**。預設是 `warn`，代表檔案不存在時只會警告、job 仍然是綠的，等到下游 job 才爆炸。設成 `error` 可以讓問題在第一時間就暴露（fail fast）。
   - `retention-days: 1` — 課堂用，避免佔用保存空間

4. **建立第二個 job。** 在 `jobs:` 底下新增 `package:`，同樣 `runs-on: ubuntu-latest`。

5. **加上相依。** 在 `package` job 加 `needs: build`。
   - 沒有 `needs:` 的 job 會**同時**開始跑（平行），那樣 `package` 會找不到 artifact
   - `needs:` 也可以是清單：`needs: [ build, lint ]`
   - 預設行為：上游 job 失敗時，下游 job 會被跳過（skipped）

6. **下載 artifact。** 在 `package` job 使用 `actions/download-artifact@v7`：
   - `name:` — 必須和上傳時**完全一樣**（大小寫也算）
   - `path:` — 下載到哪個目錄，建議 `downloaded`
   - 下載後檔案會是 `downloaded/simpleweb.jar`（artifact 內保留的是 `path` 的檔名，不含 `target/` 這層目錄）

7. **驗證檔案真的拿到了。** 加一個 step：`ls -l downloaded`、印出檔案大小，並且用 `test -f downloaded/simpleweb.jar || exit 1` 確保檔案不存在時 job 會失敗。
   > 「驗證步驟必須會失敗」是 CI 的基本功。一個永遠不會失敗的檢查等於沒有檢查。

8. **Push 並觀察。** 在 Actions 的 run 頁面你會看到：
   - 兩個 job，`package` 排在 `build` 之後（視覺上是一張流程圖）
   - run 總覽頁下方有一個 artifact 區塊，可以直接把 `simpleweb-jar` 下載到你的電腦

9. **做一次小實驗。** 把 `package` job 的 `needs: build` 註解掉再 push 一次，觀察：兩個 job 同時開始、`package` 因為找不到 artifact 而失敗。看完之後把 `needs:` 加回來。

## 概念補充：Artifact 與 Cache 的差別（本課程只需理解，不做 cache 練習）

| | **Artifact** | **Cache** |
|---|---|---|
| 目的 | 保存與傳遞**交付物** | 加速重複性工作 |
| 典型內容 | `simpleweb.jar`、測試報告、log | `~/.m2/repository` 相依套件、編譯快取 |
| 遺失的後果 | **不可接受**——那是你要部署的東西 | 可接受——最多就是慢一點，重新下載即可 |
| 是否保證存在 | 是（上傳成功就一定拿得到） | 否（cache miss 是正常狀況，流程必須照樣能跑） |
| 使用方式 | `upload-artifact` / `download-artifact` | 由 action 自行判斷 hit/miss |
| 可否手動下載 | 可以，在 run 頁面直接下載 | 不行 |

一句話記法：**cache 是為了「快」，artifact 是為了「交付」。**
兩者最大的心理差異是——**你的流程絕對不能依賴 cache 一定存在，但可以依賴 artifact 一定存在。**

> 補充：`actions/setup-java` 本身有內建的相依套件快取選項，實務上常用。本課程不做這個練習，知道有這回事即可。

## 你要自己完成的 YAML

Starter：[`starters/lab03.yml`](starters/lab03.yml)

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      # （checkout / setup-java / mvnw verify 已提供）

      # TODO 1: actions/upload-artifact@v7
      #   name / path / if-no-files-found: error / retention-days: 1

  package:
    runs-on: ubuntu-latest
    # TODO 2: needs: ???
    steps:
      # TODO 3: actions/download-artifact@v7（name 要和上傳一致）
      # TODO 4: 驗證 downloaded/simpleweb.jar 存在，不存在就 exit 1
```

## 驗收標準

- [ ] Actions run 顯示**兩個 job**，且 `package` 明確排在 `build` 之後
- [ ] 兩個 job 都是**綠色勾勾**
- [ ] run 總覽頁的 artifact 區塊出現 `simpleweb-jar`，可以下載
- [ ] `package` job 的 log 中，`ls -l downloaded` 顯示 `simpleweb.jar` 且大小 > 0
- [ ] 你能用自己的話說出「為什麼不能直接在 package job 讀 target/simpleweb.jar」
- [ ] 你能說出 artifact 與 cache 各自的用途

## 常見錯誤

| 症狀 | 原因 | 修法 |
|---|---|---|
| `Unable to find any artifacts for the associated workflow` | artifact name 打錯，或上下游名稱不一致 | 兩邊的 `name:` 必須逐字相同 |
| `package` 找不到 artifact 且比 `build` 早結束 | 忘了 `needs:` | 加上 `needs: build` |
| artifact 是空的但 job 是綠的 | `if-no-files-found` 用預設的 `warn` | 改成 `error` |
| 下載後路徑變成 `downloaded/target/simpleweb.jar` | 上傳時 `path` 寫成目錄或含萬用字元 | 上傳單一檔案時直接寫 `target/simpleweb.jar` |
| `needs:` 寫成 `need:` | 拼字 | GitHub 會回報 workflow 檔案無效 |
| log 出現 Node.js 20 deprecation 警告 | 用了舊的 artifact action major 版本 | 本課程統一使用 `upload-artifact@v7` / `download-artifact@v7` |
| upload 與 download 版本不一致 | 一邊 v7、一邊舊版 | 兩邊都要用 **v7**（artifact 的儲存格式跟著 major 版本走） |
| 上游失敗後下游沒跑，以為是設定壞了 | 這是**預設且正確**的行為 | 先修好上游 job |

## 解答

[`solutions/lab03.yml`](solutions/lab03.yml)
