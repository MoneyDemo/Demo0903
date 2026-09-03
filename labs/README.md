# GH-200 GitHub Actions — 學員實作手冊

> 課程 repo：[`MoneyDemo/20260903-GH200`](https://github.com/MoneyDemo/20260903-GH200)
> 對象：**沒有用過 GitHub Actions 的企業 Java 開發者**

## 這份手冊要帶你達成什麼

> **訓練完能自己寫 YAML，完成 Build → Test → Package → Deploy 到測試環境／正式環境，並能查看 workflow log 進行錯誤處理。**

因此這份手冊有一個刻意的設計：**所有 lab 的正文都不會給你可以直接複製貼上的完整 YAML。**
每個 lab 都提供一份 `starters/lab0X.yml` 骨架，裡面用 `# TODO:` 標出你要自己補的部分。
完整答案放在 `solutions/`，卡住時再看——但請先自己動手打過一次。**打字的過程就是學習本身。**

## Lab 一覽

| Lab | 主題 | 對應客戶模組 | 預估時間 |
|---|---|---|---|
| [Lab 01](lab01-first-workflow.md) | 第一個 workflow：觸發事件、job、step | **M1** Design and Manage Workflows | 20 分 |
| [Lab 02](lab02-build-and-test.md) | Build & Test：checkout、setup-java、`./mvnw -B verify`、Job Summary | **M1** + **M2** | 30 分 |
| [Lab 03](lab03-package-artifact.md) | 兩個 job + `needs:` + artifact 交接（artifact vs cache 概念） | **M1** | 30 分 |
| [Lab 04](lab04-deploy-test.md) | 部署到 **test**：environment、`id-token: write`、OIDC、`az vm run-command` | **M1** + **M5** | 45 分 |
| [Lab 05](lab05-prod-approval.md) | Promote 到 **production**：核准關卡、保護規則、environment secrets | **M5** Secure and Optimize Automation | 30 分 |
| [Lab 06](lab06-troubleshooting.md) | **讀 log 除錯**：四個壞掉的 workflow、debug logging、re-run failed jobs | **M2** Consume and Troubleshoot Workflows | 45 分 |
| [Lab 07](lab07-selfhosted-runner.md) | （選修）self-hosted runner、label、runner group、組織政策 | **M4** Manage GitHub Actions in the Enterprise | 30 分 |

> 本次交付沒有 Module 3。
> Lab 06 是整份手冊最重要的一個——它直接對應「能查看 workflow log 進行錯誤處理」這個目標。

### 本課程**不使用**的功能

為了讓初學者專注在主線上，以下功能本次**不會**練習，也不需要出現在你的作業中：

- Reusable workflows
- Matrix strategy
- Cache（**只講概念**，見 Lab 03 的比較表；不做練習）

## 你要部署的應用程式

一個 Spring Boot 應用，Maven 專案位於 repo 根目錄。

| 項目 | 值 |
|---|---|
| Java | **21** |
| Spring Boot | **4.1.1** |
| 建置指令 | `./mvnw -B verify`（Windows 本機：`.\mvnw.cmd -B verify`） |
| 建置產出 | **`target/simpleweb.jar`**（固定，永遠是這個檔名） |
| 端點 | `/`（HTML，顯示 environment / build SHA / hostname）、`/api/info`（JSON）、`/actuator/health` |
| 執行期環境變數 | systemd unit 直接設定 `SERVER_PORT` / `APP_ENVIRONMENT`；`app.env` 提供 `APP_BUILD_SHA` / `APP_BUILD_TIME` |

> **Maven Wrapper 已經 commit 在 repo 裡，你的機器不需要安裝 Maven。**
> 但你**需要** JDK 21。

## 目標環境

一台 Azure **Ubuntu 24.04** VM，上面跑兩個 systemd 服務：

| 環境 | systemd service | Port | Jar 路徑 | 環境變數檔 | GitHub Environment |
|---|---|---|---|---|---|
| 測試 | `simpleweb-test` | **8080** | `/opt/simpleweb/test/simpleweb.jar` | `/opt/simpleweb/test/app.env` | `test` |
| 正式 | `simpleweb-prod` | **8081** | `/opt/simpleweb/prod/simpleweb.jar` | `/opt/simpleweb/prod/app.env` | `production`（有**核准關卡**） |

systemd unit 以 `Environment=` 固定 `SERVER_PORT` / `APP_ENVIRONMENT`，並透過
**`app.env`** 讀取 build metadata。該檔須可被 service 讀取（本課使用
`root:root` / `0644`）。部署只負責 `APP_BUILD_SHA` / `APP_BUILD_TIME`。

部署方式：`azure/login@v3` 以 **OIDC** 登入，再用 `az vm run-command invoke` 操作 VM。

### 交付路徑與信任邊界

build job 會把 `target/simpleweb.jar` 發佈成一個固定 tag 的 pre-release **`build-<commit-sha>`**
（`gh release create` / `gh release upload --clobber`，需要 `contents: write`）。
部署時只把**公開、匿名可下載**的 asset URL 傳給 VM：

```
https://github.com/<owner>/<repo>/releases/download/build-<commit-sha>/simpleweb.jar
```

> 🔒 **原則：絕對不要把 `GITHUB_TOKEN` 或任何憑證傳給 VM 或 `az vm run-command --parameters`。**
> VM 是部署目標，不是可信任的執行環境；傳給 run-command 的參數會留在 Azure 的紀錄裡。
> 本課程所有傳給 VM 的參數都是非機密資訊（公開 URL、環境名稱、服務名稱、commit SHA）。

因此 **Lab 04／05 需要你的 repo 是 public**。Lab 03 教的 workflow artifact 仍然保留，
它負責 job 之間的交接與人工下載除錯；release asset 則是給外部機器用的公開通道。

### 🔴 關於 VM 的 IP

**VM 的 public IP 在編寫本手冊時尚未確定。**
手冊中一律寫成 `<VM_PUBLIC_IP>`（文字）或 `${{ vars.VM_PUBLIC_IP }}`（YAML）。

**講師會在課堂上公布實際 IP**，拿到之後請把它設成你 repo 的 repository variable：

```bash
gh variable set VM_PUBLIC_IP --repo <your-account>/20260903-GH200 --body "<實際IP>"
```

**不要把 IP 寫死在 YAML 裡**——這既是好習慣，也是為了 IP 變動時不用改一堆檔案。

## 前置需求檢查表

開課前請逐項確認：

- [ ] **GitHub 帳號**，並已加入課程使用的組織／可存取課程 repo
- [ ] **Git** 已安裝（`git --version`）
- [ ] **GitHub CLI (`gh`)** 已安裝並登入（`gh auth status` 顯示已登入）
- [ ] **JDK 21** 已安裝（`java -version` 顯示 21 或以上）
- [ ] **不需要**安裝 Maven（用 repo 內的 Maven Wrapper）
- [ ] 編輯器（建議 VS Code，安裝 YAML 擴充套件並開啟「顯示空白字元」）
- [ ] 瀏覽器可以連到 GitHub
- [ ] 你自己帳號底下有一份課程 repo（fork 或 clone），且 **Actions 已啟用**
- [ ] repo 中已建立 environment：`test` 與 `production`
- [ ] 若講師已授權你執行 CD：repo secrets `AZURE_CLIENT_ID` /
  `AZURE_TENANT_ID` / `AZURE_SUBSCRIPTION_ID`
- [ ] repo variables：`AZURE_RESOURCE_GROUP` / `AZURE_VM_NAME` / `VM_PUBLIC_IP`（講師提供）
- [ ] 你的 repo 是 **public**（Lab 04／05 的 VM 需要匿名下載 release asset）

### 一鍵設定腳本

上面 repo/environment 設定可以用腳本完成：

**Windows（PowerShell）**
```powershell
cd scripts
.\setup-student-repo.ps1
```

**Linux / macOS（bash）**
```bash
cd scripts
chmod +x setup-student-repo.sh
./setup-student-repo.sh
```

腳本會檢查工具、檢查 repo 可見度（public）、fork + clone repo、啟用 Actions、建立兩個 environment，並印出下一步。
只有在講師確認**你的 repository 已有專屬 OIDC federated credential 與 Azure RBAC**
之後，才帶參數補上 secrets／variables：

```powershell
.\setup-student-repo.ps1 -VmPublicIp <VM_PUBLIC_IP> -AzureResourceGroup <RG> -AzureVmName <VM> `
    -AzureClientId <ID> -AzureTenantId <ID> -AzureSubscriptionId <ID>
```

```bash
VM_PUBLIC_IP=<VM_PUBLIC_IP> AZURE_RESOURCE_GROUP=<RG> AZURE_VM_NAME=<VM> \
AZURE_CLIENT_ID=<ID> AZURE_TENANT_ID=<ID> AZURE_SUBSCRIPTION_ID=<ID> \
  ./setup-student-repo.sh
```

腳本**不會**刪除任何東西、不會覆寫既有目錄、也不會硬編任何 token（一律使用你 `gh` 的既有登入狀態）。

### Lab 04／05 的身分邊界（重要）

OIDC federated credential 會精確綁定 GitHub repository 與 Environment。講師為
`MoneyDemo/20260903-GH200` 建立的信任，**不會自動信任你的 fork**；只複製
`AZURE_CLIENT_ID` 等三個 ID 到 fork 仍會得到 `AADSTS700213`。

本課預設：

- Lab 01–03、06：在自己的 fork 實作並執行。
- Lab 04–05：學生先在 fork 寫完 YAML、由講師 review；實際 deployment 由講師在
  class repo 示範，或讓已取得 class repo write access 的學員在指定 branch 操作。
- 若客戶要求每位學員都部署：講師必須為**每一個 fork**建立精確的 federated
  credential 並配置最小範圍 RBAC；setup script 不會也不應自動取得這項 Azure 權限。

**不要把講師的 SSH private key、PAT 或長期 Azure client secret 發給學員作為替代方案。**

### `production` 的核准關卡要自己設

API 可以建立 environment，但 **required reviewer 請你自己在 repo 設定頁的 Environments 中加上**（把你自己加進去即可）。
Lab 05 需要它才能體驗核准流程。

## 檔案結構

```
labs/
├── README.md                     ← 你正在看的這份
├── lab01-first-workflow.md
├── lab02-build-and-test.md
├── lab03-package-artifact.md
├── lab04-deploy-test.md
├── lab05-prod-approval.md
├── lab06-troubleshooting.md
├── lab07-selfhosted-runner.md
├── starters/                     ← 有 TODO 的骨架，從這裡開始
│   ├── lab01.yml ... lab07.yml
│   └── lab06-broken-1.yml ... lab06-broken-4.yml   ← Lab 06 的四道題目
├── solutions/                    ← 完整解答，卡住再看
│   ├── lab01.yml ... lab07.yml
│   └── lab06-fixed-1.yml ... lab06-fixed-4.yml
└── scripts/
    ├── setup-student-repo.ps1
    └── setup-student-repo.sh
```

## 使用的 action 版本

本手冊統一使用下列版本，請照抄，不要自行改版號（不同大版號的參數可能不相容）：

| Action | 版本 | 用途 |
|---|---|---|
| `actions/checkout` | **v5** | 把原始碼抓到 runner |
| `actions/setup-java` | **v6** | 安裝 JDK（temurin / 21） |
| `actions/upload-artifact` | **v7** | 上傳建置產出 |
| `actions/download-artifact` | **v7** | 下載建置產出 |
| `azure/login` | **v3** | 以 OIDC 登入 Azure |

> ℹ️ **為什麼 artifact 系列是 v7？**
> artifact 系列的 **v4** 執行時會在 log 中出現 **Node.js 20 deprecation 警告**
> （該 major 版本綁定的 runner runtime 已進入淘汰期）。
> v7 改用較新的 Node runtime，警告即消失。功能與參數（`name` / `path` /
> `if-no-files-found` / `retention-days`）與舊版相同，Lab 03 的教學內容不受影響。
> 其餘 action 維持 `checkout@v5`、`setup-java@v6`、`azure/login@v3`，與課堂 workflow 一致。
>
> 在 log 中看到 deprecation 警告時，正確的處理方式就是**升級 action 的 major 版本**，
> 而不是忽略它——這也是 Lab 06「讀 log」的延伸練習。

## 如果你落後了

課堂節奏很快，落後是正常的。**不要停在原地硬追**，用下面的方式跟上：

1. **先確認你落後在哪一個 lab。** 每個 lab 的「驗收標準」就是檢查點——從最後一個你能全部打勾的 lab 開始算。

2. **直接使用 `solutions/` 追上進度。** 把對應的解答檔複製到 `.github/workflows/`，改成該 lab 要求的檔名，push 讓它跑綠，你就回到主線了。
   例如你卡在 Lab 03，想跟上 Lab 04：
   ```bash
   cp labs/solutions/lab03.yml .github/workflows/lab03-artifact.yml
   git add . && git commit -m "catch up lab03" && git push
   ```

3. **但請務必回頭補上。** 用解答追進度只是為了不錯過現場示範，**課後一定要自己重打一次**——客戶的目標是「你能自己寫 YAML」，不是「你有一份能跑的 YAML」。
   建議做法：把解答檔關掉，照著該 lab 的「你要自己完成的 YAML」骨架**憑記憶重打**，寫不出來的地方才回去看。

4. **各 lab 的相依關係：**
   ```
   Lab01 → Lab02 → Lab03 → Lab04 → Lab05
                              ↘
                               Lab06（建議做完 Lab04 再做，才能重現 OIDC 那一題）
   Lab07（選修，只需要 Lab01 的基礎）
   ```
   - Lab 06 的 Case 1、2、4 **不需要** Azure 設定，隨時可以做
   - Lab 06 的 Case 3 需要 Azure secrets；若還沒設定好，可以只讀 log 訊息並推理原因

5. **真的追不上就跳到 Lab 06。** 如果時間只夠再做一個 lab，做 Lab 06。
   會寫 YAML 但不會除錯，回公司第一次卡住就前功盡棄；
   會除錯的人，就算 YAML 忘了怎麼寫，也有辦法自己查到答案並修好。

## 給講師的小提醒

- 課前請把實際的 `VM_PUBLIC_IP` / `AZURE_RESOURCE_GROUP` / `AZURE_VM_NAME` 與三個 Azure ID 準備好發給學員
- Azure 端的 federated credential 需涵蓋每位學員 repo 的 `test` 與 `production` environment
- VM 的網路安全群組需要開放 **8080** 與 **8081**
- VM 需能對外連到 `github.com` 下載 release asset；學員的 fork 需維持 **public**
- 兩個 systemd unit 需直接設定各自的 `SERVER_PORT` / `APP_ENVIRONMENT`，並以
  `EnvironmentFile` 指向 `/opt/simpleweb/{test,prod}/app.env` 讀取 `APP_BUILD_*`
- Lab 07 若要實作，需提供 VM 的 SSH 連線方式
