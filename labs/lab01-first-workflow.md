# Lab 01 — 你的第一個 workflow

## 學習目標

做完這個 lab，你應該可以：

- 說出 workflow 檔案「必須」放在哪個目錄、副檔名是什麼
- 自己手寫一份最小可執行的 workflow YAML
- 分辨 `on` / `jobs` / `steps` 三個層級的關係與縮排規則
- 同時設定「push 自動觸發」與「手動觸發（`workflow_dispatch`）」
- 在 Actions 頁面找到某一次執行、展開某一個 step、看到它印出的內容

## 對應模組

**Module 1 — Design and Manage Workflows**（events / triggers、jobs 與 steps、`workflow_dispatch`）

## 前置需求

- 已完成 [README.md](README.md) 的「前置需求檢查表」
- 你自己帳號底下已有一份 class repo（fork 或 clone 皆可），Actions 已啟用
- 本機有 `git`，或你打算直接用 GitHub 網頁編輯器建立檔案

## 步驟

1. **確認檔案位置。** 在 repo 根目錄下建立 `.github/workflows/` 目錄（注意開頭那個點，以及 `workflows` 是複數）。GitHub **只會**掃描這個目錄底下的 `*.yml` / `*.yaml`。放在 `workflows/`、`.github/workflow/`、或子資料夾裡都不會被執行——這是新手最常見的第一個坑。

2. **建立檔案** `.github/workflows/lab01-hello.yml`。起手式請從 [`starters/lab01.yml`](starters/lab01.yml) 複製，然後**自己把 TODO 打完**。

3. **補上 `name:`。** 這是顯示在 Actions 左側清單的名稱。省略的話 GitHub 會用檔名代替。

4. **補上觸發事件 `on:`。** 你需要兩種觸發：
   - `push`，而且限定在 `main` 分支（用 `branches:` 過濾）
   - `workflow_dispatch`，讓你可以在網頁上按按鈕手動執行

   `workflow_dispatch` 後面不需要任何值，寫成 `workflow_dispatch:` 就好。這是 YAML 的「key 有值為 null」寫法。

5. **定義一個 job。** `jobs:` 底下的 key 就是 job id（例如 `hello:`）。每個 job 至少要有 `runs-on:`，告訴 GitHub 要用哪一種 runner。本課程一律使用 GitHub 託管的 Ubuntu runner，標籤是 `ubuntu-latest`。

6. **加入 steps。** `steps:` 是一個**清單**，每一項都以 `- ` 開頭。最簡單的 step 只有 `name:` 和 `run:`：
   - 第一個 step 印出一段自訂訊息，訊息中要包含 `${{ github.run_number }}`
   - 第二個 step 印出 branch (`github.ref_name`) 與 commit SHA (`github.sha`)

   `${{ }}` 是 GitHub Actions 的 expression 語法，會在執行前先被替換成實際的值。

7. **理解縮排規則。** YAML 用空白（**不能用 Tab**）表示層級。本課程統一：每一層縮排 2 個空白，清單項目的 `- ` 也算縮排。建議在 VS Code 開啟「顯示空白字元」。

8. **Commit 並 push 到 `main`。**
   ```bash
   git add .github/workflows/lab01-hello.yml
   git commit -m "Add lab01 hello workflow"
   git push
   ```

9. **觀察執行。** 到 repo 頁面上方的 **Actions** 分頁：
   - 左側會出現你的 workflow 名稱 `Lab01 Hello`
   - 中間是每一次的執行紀錄（run），點進去
   - 點左側的 job 名稱 `hello`，右邊會展開每一個 step
   - 點 step 名稱可以展開／收合它的 log

10. **試試手動觸發。** 在 Actions 頁面選到這個 workflow，畫面上會出現手動執行的按鈕（因為你加了 `workflow_dispatch`）。按下去再跑一次，注意 `github.event_name` 這次會是 `workflow_dispatch` 而不是 `push`。
    > 手動觸發的按鈕只有在 workflow 檔案**已經存在於預設分支**時才會出現。如果你在其他分支加 `workflow_dispatch`，按鈕不會出現。

## 你要自己完成的 YAML

Starter：[`starters/lab01.yml`](starters/lab01.yml)

```yaml
name: Lab01 Hello

# TODO 1: 加入觸發事件區塊 on:
#   a) push 到 main 分支
#   b) workflow_dispatch

jobs:
  # TODO 2: 把 job id 改成 hello
  todo-job-id:
    # TODO 3: 指定 GitHub 託管的 Ubuntu runner
    runs-on: TODO-RUNNER-LABEL

    steps:
      # TODO 4: 印出含 ${{ github.run_number }} 的訊息
      - name: Say hello
        run: echo "TODO 換成你自己的訊息"

      # TODO 5: 印出 branch 與 commit SHA
```

## 驗收標準

- [ ] 檔案路徑正確：`.github/workflows/lab01-hello.yml`
- [ ] push 到 `main` 後，Actions 頁面自動出現一次新的 run
- [ ] 該 run 的 job `hello` 顯示**綠色勾勾**
- [ ] 展開 step，log 中可以看到你的自訂訊息，且執行編號是實際數字（不是字面的 `${{ github.run_number }}`）
- [ ] Actions 頁面上出現手動執行按鈕，按下後可再跑一次
- [ ] 手動觸發的那一次，log 中 `Event` 顯示為 `workflow_dispatch`

## 常見錯誤

| 症狀 | 原因 | 修法 |
|---|---|---|
| Actions 頁面完全沒有東西 | 檔案不在 `.github/workflows/`，或 Actions 沒啟用 | 檢查路徑；到 repo 設定把 Actions 打開 |
| 檔案被標示為 invalid workflow file | YAML 語法錯（縮排、Tab、少冒號） | 用 VS Code 的 YAML 檢查；把 Tab 全換成空白 |
| 手動執行按鈕沒出現 | `workflow_dispatch` 沒加，或檔案還不在預設分支上 | 先把改動合併／push 到 `main` |
| log 印出字面的 `${{ github.run_number }}` | 用了單引號包住整串，或寫成 `$（github.run_number）` | expression 一律用 `${{ }}`，`run:` 內用雙引號 |
| `You have an error in your yaml syntax` 指向 steps | `steps` 的項目沒有 `- ` 開頭 | `steps:` 底下每個 step 都要 `- ` |
| push 了卻沒觸發 | `branches:` 過濾寫成別的分支名 | 確認你的預設分支到底叫 `main` 還是 `master` |

## 解答

[`solutions/lab01.yml`](solutions/lab01.yml)
