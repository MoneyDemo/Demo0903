# Lab 04 — 部署到 test 環境（OIDC + az vm run-command）

## 學習目標

做完這個 lab，你應該可以：

- 使用 `environment:` 把 job 綁定到 GitHub Environment，並在 Actions 頁面看到部署連結
- 把建置產出發佈成 **rolling pre-release `build-<commit-sha>`**，成為 VM 可以匿名取用的下載點
- 說明 OIDC 與「把密碼存成 secret」的差別，以及為什麼 OIDC 比較安全
- 正確設定 `permissions:`：workflow 層級最小、build job 提升為 `contents: write`、deploy job 只要 `id-token: write`
- 用 `azure/login@v3` 以 OIDC 登入 Azure，完全不需要保存長期憑證
- 用 `az vm run-command invoke` 把 jar 送上 VM、更新 `app.env`、重啟 systemd 服務
- 說出「**永遠不要把 token 交給部署目標機器**」這個信任邊界原則
- 用 smoke test 驗證部署結果，而不是「看起來綠色就當作成功」

## 對應模組

**Module 1 — Design and Manage Workflows**（secrets、變數、job 相依）
**Module 5 — Secure and Optimize Automation**（最小權限 `permissions`、OIDC to Azure、environments、信任邊界）

## 前置需求

> **預設由講師實跑。** 你的 fork 必須有自己的 OIDC federated credential 與 Azure
> RBAC 才能登入；講師 class repo 的 credential 不會套用到 fork。若未獲授權，請完成
> YAML 並對照講師的實際 workflow log，不要要求或共用講師的長期密鑰。

- 已完成 [Lab 03](lab03-package-artifact.md)
- 你的 repo 已建立 GitHub Environment：**`test`**（`scripts/setup-student-repo.*` 會幫你建）
- 你的 repo 是 **public**（VM 需要匿名下載 release asset；fork 課程 repo 預設就是 public）
- 你的 repo 已設定下列 **secrets**（講師提供實際值）：
  - `AZURE_CLIENT_ID`
  - `AZURE_TENANT_ID`
  - `AZURE_SUBSCRIPTION_ID`
- 你的 repo 已設定下列 **variables**（講師提供實際值）：
  - `AZURE_RESOURCE_GROUP`
  - `AZURE_VM_NAME`
  - `VM_PUBLIC_IP` ← **課堂上才會拿到，講義中一律寫 `<VM_PUBLIC_IP>`**

> ⚠️ **VM 的 public IP 目前未知。** 本講義所有地方都以 `<VM_PUBLIC_IP>` 或 `${{ vars.VM_PUBLIC_IP }}` 表示，講師會在課堂上公布實際 IP，請把它設定成 repository variable，**不要**寫死在 YAML 裡。

### 目標環境契約（不可更動）

| 環境 | systemd service | Port | Jar 路徑 | 環境變數檔 |
|---|---|---|---|---|
| test | `simpleweb-test` | 8080 | `/opt/simpleweb/test/simpleweb.jar` | `/opt/simpleweb/test/app.env` |
| production | `simpleweb-prod` | 8081 | `/opt/simpleweb/prod/simpleweb.jar` | `/opt/simpleweb/prod/app.env` |

systemd unit 直接用 `Environment=` 設定 `SERVER_PORT` / `APP_ENVIRONMENT`，再透過
**`app.env`** 讀取 `APP_BUILD_SHA` / `APP_BUILD_TIME`。這個檔案必須可被 service
讀取（本課使用 `root:root`、`0644`）。

## 步驟

1. 建立 `.github/workflows/lab04-deploy-test.yml`，從 [`starters/lab04.yml`](starters/lab04.yml) 開始。

2. **先看懂 OIDC 在做什麼。** 傳統做法是把一組 Azure service principal 的密碼／憑證存成 GitHub secret，長期有效、外洩就完蛋。OIDC 的做法是：
   1. workflow 執行時，向 GitHub 索取一個**短期、綁定這個 repo 與 environment** 的 id token
   2. 拿這個 token 去換 Azure 的存取權杖
   3. 用完即失效

   所以 `AZURE_CLIENT_ID` 等三個值**不是密碼**，只是識別用的 ID。真正的信任建立在 Azure 端設定的 federated credential 上（由講師事先建好）。

3. **想清楚 jar 要怎麼送上 VM。** 這是本 lab 的設計重點：

   > **VM 是部署目標，不是可信任的執行環境。**
   > 任何交給 `az vm run-command` 的參數，都會被 Azure 記錄下來、也會出現在 VM 上。
   > 所以**絕對不要**把 `GITHUB_TOKEN` 或任何憑證傳給 VM。

   正確做法：讓 jar 變成一個**公開可匿名下載的 URL**，VM 只需要 `curl`，不需要任何身分。
   我們用 GitHub Release 來做這件事——把 jar 發佈成一個固定 tag 的 **pre-release `build-<commit-sha>`**，每次建置就覆蓋同一個 asset。

   | | workflow artifact（Lab 03） | release asset（本 lab） |
   |---|---|---|
   | 用途 | job 之間交接、人工下載除錯 | 給**外部系統**（VM）取用 |
   | 存取方式 | 需要認證（API + token） | public repo 可**匿名** `curl` |
   | 保存期限 | 有 retention 限制 | 直到你刪掉它 |

   Lab 03 學到的 artifact 仍然保留（方便你從 run 頁面下載 jar 除錯），這裡只是**多加一條給機器用的公開通道**。

4. **build job：提升權限並發佈 release。**
   - workflow 層級維持 `permissions: contents: read`
   - `build` job 加上 `permissions: contents: write`（建立／更新 release 需要）
   - 沿用 Lab 03 的 `upload-artifact`
   - 再加一個 step 發佈 release。`gh` CLI 在 GitHub 託管 runner 上已預裝，只要給它 `GH_TOKEN` 環境變數即可：
     - 用 `gh release view build-<commit-sha>` 判斷 release 是否已存在，不存在才 `gh release create ... --prerelease`
     - 用 `gh release upload build-<commit-sha> target/simpleweb.jar --clobber` 覆蓋既有 asset

   **想一下：`--clobber` 是做什麼的？** 沒有它，第二次上傳同名 asset 會直接失敗。這就是「rolling tag」能持續運作的關鍵。

   > 教學用的簡化：真實的正式環境會用**不可變的版本化 tag**（例如 `v1.4.2`）搭配保留歷史版本，才能精確回溯「上線的是哪一版」。`build-<commit-sha>` 這種滾動 tag 只適合課堂與開發環境。

5. **建立 `deploy-test` job**，並補上：
   - `needs: build`
   - `environment:` — `name: test`，另外設 `url:` 指向 `http://${{ vars.VM_PUBLIC_IP }}:8080/`，這樣 Actions 頁面上會出現可點擊的部署連結
   - `permissions:` — 這個 job 只需要兩個：
     | 權限 | 為什麼 |
     |---|---|
     | `contents: read` | 基本讀取 |
     | `id-token: write` | **OIDC 必要**，沒有它 `azure/login` 一定失敗 |

     注意它**不需要** `contents: write`——發佈是 build job 的責任。這就是逐 job 收斂權限的實際做法。

   > 注意：job 層級的 `permissions:` 會**整組覆蓋** workflow 層級的設定，需要的權限必須一次列齊。

6. **Azure 登入。** 使用 `azure/login@v3`，在 `with:` 提供 `client-id` / `tenant-id` / `subscription-id`，值都從 `${{ secrets.* }}` 取得。

7. **部署。** 用 `az vm run-command invoke` 在 VM 上執行一段 shell script。starter 已經把 VM 上要跑的 script 寫好給你（它做這些事）：
   1. 匿名 `curl -fsSL` 下載 `build-<commit-sha>` 的 `simpleweb.jar`（**沒有任何 Authorization header**）
   2. `unzip -tq` 驗證下載回來的是完整的 jar（下載到一半的檔案會在這裡就被擋下來）
   3. `install -m 0644 -o root -g root` 放到 `/opt/simpleweb/test/simpleweb.jar`
   4. **就地更新** `app.env`：先用 `sed` 刪掉舊的 `APP_BUILD_SHA` / `APP_BUILD_TIME`，再 append 新的
   5. `chown root:root` + `chmod 0644` 確保 systemd 讀得到
   6. `systemctl restart simpleweb-test`
   7. `systemctl is-active` 確認服務起來了

   你要補的是這幾行：
   - `--resource-group "${{ vars.AZURE_RESOURCE_GROUP }}"`
   - `--name "${{ vars.AZURE_VM_NAME }}"`
   - `--parameters` 裡的 `ENV_DIR`（填 `test`）與 `SERVICE`（填 `simpleweb-test`）

   `az vm run-command invoke --command-id RunShellScript` 的 `--parameters` 會依序變成 script 裡的 `$1 $2 $3 ...`。
   本 lab 傳進去的四個值 —— jar 的公開 URL、環境目錄、服務名稱、commit SHA —— **全部都是非機密資訊**，這是刻意的設計。

   > **為什麼練習使用 `sed` + append？**
   > 本課的 `app.env` 目前只放 `APP_BUILD_*`，直接覆寫也能運作；這裡刻意練習
   > 「只更新自己負責的設定」這個通用操作紀律。Port 與 environment 由 systemd
   > unit 的 `Environment=` 固定，不受此檔覆寫影響。

8. **Smoke test。** 部署完不要相信「綠色 = 成功」，一定要實際打一次服務：
   - 對 `http://${{ vars.VM_PUBLIC_IP }}:8080/actuator/health` 做 `curl -fsS`
   - 服務啟動需要時間，請用迴圈重試（建議 12 次、每次間隔 5 秒）
   - 全部失敗就 `exit 1` 讓 job 變紅
   - `curl` 的 `-f` 參數很重要：沒有它，HTTP 500 也會被視為成功

9. **Push 並觀察。** 在 run 頁面你應該看到：
   - `build` job 完成後，repo 的 Releases 出現（或更新）標示為 pre-release 的 `build-<commit-sha>`
   - `deploy-test` job 上標示著 environment `test`
   - job 完成後出現指向 `http://<VM_PUBLIC_IP>:8080/` 的連結

10. **用瀏覽器驗證。** 開啟 `http://<VM_PUBLIC_IP>:8080/`，頁面上應該顯示 environment 為 `test`、以及這次的 build SHA。再看 `http://<VM_PUBLIC_IP>:8080/api/info` 的 JSON。

### 附錄：SSH 變體（講師示範用，非必做）

若 VM 對外網路受限、無法連到 GitHub 下載 release asset，另一種常見做法是在 runner 上 `download-artifact` 取回 jar，再用 SSH／`scp` 推上 VM（私鑰存成 secret）。優點是檔案傳輸最單純、也不需要 public repo，缺點是又回到「保管長期憑證」的老路，而且 runner 的對外 IP 不固定、防火牆不好收斂。本課程主線採用 OIDC + release asset + `az vm run-command`，就是為了**同時**避免管理長期憑證與避免把憑證送到目標機器上。

## 你要自己完成的 YAML

Starter：[`starters/lab04.yml`](starters/lab04.yml)（含完整的 VM 端 script，你只要補參數）

```yaml
permissions:
  contents: read          # workflow 層級：最小

jobs:
  build:
    runs-on: ubuntu-latest
    # TODO 1: permissions.contents = ?（要建立 release）
    steps:
      # （checkout / setup-java / mvnw verify 已提供）
      # TODO 2: upload-artifact@v7（名稱 simpleweb-jar）
      # TODO 3: gh release create/upload build-<commit-sha> --prerelease --clobber

  deploy-test:
    runs-on: ubuntu-latest
    # TODO 4: needs:
    # TODO 5: environment: name + url（port 8080）
    # TODO 6: permissions: contents: read / id-token: write
    steps:
      # TODO 7: azure/login@v3（OIDC）
      # TODO 8: az vm run-command invoke
      #         補 --resource-group / --name / ENV_DIR / SERVICE
      #         JAR_URL = .../releases/download/build-<commit-sha>/simpleweb.jar
      # TODO 9: smoke test /actuator/health，重試 12 次
```

## 驗收標準

- [ ] `build` job 完成後，repo 的 Releases 中有 **`build-<commit-sha>`**，標示為 **pre-release**，且附件是 `simpleweb.jar`
- [ ] 你可以在**未登入**的瀏覽器（或無痕視窗）直接下載該 asset ——證明它是匿名可取用的
- [ ] Actions run 中 `deploy-test` job 顯示**綠色勾勾**，且標示 environment `test`
- [ ] `Azure login (OIDC)` step 成功，log 中沒有任何憑證明文
- [ ] `az vm run-command invoke` 的參數中**沒有任何 token**（只有公開 URL、`test`、`simpleweb-test`、SHA）
- [ ] run-command 的輸出中可以看到 `systemctl is-active` 回傳 `active`
- [ ] smoke test step 成功，`curl` 對 `:8080/actuator/health` **回傳 200**
- [ ] 瀏覽器開 `http://<VM_PUBLIC_IP>:8080/`，頁面顯示 **environment = test**
- [ ] `http://<VM_PUBLIC_IP>:8080/api/info` 回傳的 JSON 中，build SHA 等於你這次的 commit SHA
- [ ] job 頁面上出現指向 test 環境的連結

## 常見錯誤

> **控制平面綠燈不等於 VM script 成功。** `az vm run-command invoke` 可能在
> VM script 已失敗時仍以 control-plane `Provisioning succeeded` 結束。解答會擷取
> `value[].message`、要求 VM 最後輸出 `DEPLOY_OK`，並在安裝前用 SHA-256 sidecar
> 驗證 jar；smoke test 還會確認 `/api/info` 的 `buildSha` 是本次 commit。
>
> Run Command 的 Linux script 由 `/bin/sh` 執行，因此 VM 端使用 POSIX
> `set -eu`，不可使用 Bash 專屬的 `set -o pipefail`。

| 症狀 | 原因 | 修法 |
|---|---|---|
| `Unable to get ACTIONS_ID_TOKEN_REQUEST_URL env variable` | 少了 `id-token: write` | 在 deploy job 的 `permissions:` 補上 |
| `gh release create` 回 `HTTP 403` | build job 少了 `contents: write` | 在 build job 加 `permissions: contents: write` |
| `gh release upload` 說 asset 已存在 | 沒加 `--clobber` | 加上 `--clobber` 覆蓋 |
| `gh: To use GitHub CLI ... authenticate` | 沒設 `GH_TOKEN` 環境變數 | `env: GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}` |
| VM 上 `curl` 回 404 | release 還沒建立、asset 名稱不符，或 repo 是 private | 確認 build job 已跑過；確認 repo 為 public |
| `AADSTS70021: No matching federated identity record found` | Azure 端的 federated credential 沒有涵蓋你的 repo／environment | 請講師確認設定；確認 `environment: test` 名稱完全一致 |
| `Resource group 'null' could not be found` | `vars.AZURE_RESOURCE_GROUP` 沒設定（未定義的 vars 會變成空字串） | 到 repo 的 Variables 設定補上 |
| 變數名稱找不到 | 用了舊名稱 `VM_RESOURCE_GROUP` / `VM_NAME` | 正確名稱是 `AZURE_RESOURCE_GROUP` / `AZURE_VM_NAME` |
| Build SHA 仍是舊值 | `app.env` 沒更新，或 service 沒 restart | 檢查 `APP_BUILD_*` 並讀 `journalctl -u simpleweb-test` |
| 服務起不來，`journalctl` 顯示讀不到環境變數檔 | `app.env` 權限或擁有者不對 | `chown root:root` + `chmod 0644` |
| `systemctl restart` 失敗 permission denied | script 沒有用 `sudo` | 確認 script 內的指令都有 `sudo` |
| smoke test 一直失敗但服務其實有起來 | 網路安全群組沒開 8080，或 IP 填錯 | 確認 `VM_PUBLIC_IP`；請講師確認 NSG |
| smoke test 秒失敗 | 沒有等服務啟動 | 加上重試迴圈與 `sleep` |
| 頁面顯示的 SHA 還是舊的 | 服務沒重啟，或 jar 沒真的被覆蓋 | 看 run-command 的輸出確認 `install` 與 `restart` 都執行了 |

## 解答

[`solutions/lab04.yml`](solutions/lab04.yml)
