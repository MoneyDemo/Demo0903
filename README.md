# SimpleWeb（GH-200 示範應用程式）

這是 **GH-200 GitHub Actions** 課程使用的 Java 示範網站。它刻意寫得很小，因為課程的主角是
GitHub Actions workflow，不是這支應用程式。

它做的事只有一件：**用一個超大的顏色橫幅告訴你「我是哪個環境、我是哪一版」**，
所以只要打開瀏覽器，全班就能立刻確認剛剛那次部署到底有沒有生效。

## 課程入口

- **學員練習手冊**：[labs/README.md](labs/README.md)
- **Workflow 範例**：[.github/workflows/](.github/workflows/)
- **Test 環境**：<http://20.210.89.243:8080>
- **Production 環境**：<http://20.210.89.243:8081>

### 漸進式 Workflow

| No. | Workflow | 學習重點 |
| --- | --- | --- |
| 01 | `01.build.yml` | 第一個 workflow、trigger、job、step |
| 02 | `02.build-test.yml` | CI、測試、log、job summary |
| 03 | `03.package-artifact.yml` | `needs`、artifact、job 間傳檔 |
| 04 | `04.deploy-test.yml` | OIDC 登入 Azure、部署到 test |
| 05 | `05.deploy-prod.yml` | GitHub Environment、approval gate |
| 06 | `06.full-pipeline.yml` | Build → Test → Package → Deploy |
| 07 | `07.deploy-ssh.yml` | SSH 與 OIDC 安全性對照 |
| 08 | `08.selfhosted-runner.yml` | Self-hosted runner（選修） |
| 09 | `09.troubleshooting.yml` | 故意失敗，用 workflow log 找錯 |

| 環境 (`APP_ENVIRONMENT`) | 橫幅顏色 |
| --- | --- |
| `test` | 藍色 |
| `production` | 紅／橘色 |
| `local`（預設，含任何無法辨識的值） | 灰色 |

## 技術規格

| 項目 | 內容 |
| --- | --- |
| Spring Boot | 4.1.1 |
| Spring Framework | 7.0.9（由 Spring Boot 管理） |
| Java | 21（本機實測 OpenJDK 21.0.11 LTS） |
| 建置工具 | Maven Wrapper（**不需要**先安裝 Maven） |
| groupId / artifactId / version | `money.gh200` / `simpleweb` / `1.0.0` |
| 主類別 | `money.gh200.simpleweb.SimpleWebApplication` |
| 建置產出 | `target/simpleweb.jar`（`<finalName>` 固定，部署腳本寫死這個路徑） |

樣式表放在 `src/main/resources/static/css/site.css`，**不使用任何 CDN**，
整個頁面不會對外連線，因此在網路受限的 VM 上也能正常顯示。

## 在本機執行

需求：只要有 **JDK 21** 就好，不需要安裝 Maven（`mvnw` 會自己下載 Maven）。

```powershell
# 啟動（預設 http://localhost:8080，環境為 local）
.\mvnw spring-boot:run
```

想模擬部署後的樣子，可以先設環境變數再啟動：

```powershell
$env:APP_ENVIRONMENT = "test"
$env:APP_BUILD_SHA   = "a1b2c3d"
$env:APP_BUILD_TIME  = "2026-09-03T00:10:00Z"
.\mvnw spring-boot:run
```

打包並直接跑 jar：

```powershell
.\mvnw -B package
java -jar target\simpleweb.jar
```

> Linux／macOS 或 CI runner 上請改用 `./mvnw`。

## 執行測試

```powershell
# 單元測試 + web slice 測試 + 整合測試，全部跑一遍並打包
.\mvnw verify
```

`verify` 會依序執行：

| 測試 | 類型 | 內容 |
| --- | --- | --- |
| `InfoServiceTest` | 單元測試（Surefire） | 驗證環境名稱正規化、預設值、橫幅顏色對應、主機名稱查詢失敗的容錯 |
| `HomeControllerTest` | Web slice（`@WebMvcTest`） | 驗證 `/` 回 200，且畫面上有環境名稱與 build 資訊 |
| `SimpleWebApplicationIT` | 整合測試（Failsafe，`@SpringBootTest(webEnvironment = RANDOM_PORT)`） | 真的啟動 server（**隨機 port，不會佔用 8080**）並打 `/`、`/api/info`、`/actuator/health` |

只跑單元測試：`.\mvnw test`（整合測試 `*IT` 由 Failsafe 在 `verify` 階段才執行）。

## Endpoints

| 路徑 | 方法 | 說明 |
| --- | --- | --- |
| `/` | GET | HTML 首頁，大字顯示環境、版本、build SHA、build 時間、hostname、伺服器時間、Java 版本 |
| `/api/info` | GET | 與首頁相同的資訊，JSON 格式 |
| `/actuator/health` | GET | Spring Boot Actuator health check（只開放 `health` 與 `info` 兩個 endpoint） |

`/api/info` 回應範例：

```json
{
  "application": "SimpleWeb",
  "version": "1.0.0",
  "environment": "test",
  "buildSha": "a1b2c3d4e5",
  "buildTime": "2026-09-03T00:10:00Z",
  "hostname": "MONEY-PC",
  "javaVersion": "21.0.11",
  "serverTime": "2026-09-03 00:10:13 CST"
}
```

## 環境變數

所有執行期設定都走環境變數，**不會**被編進 jar 裡；部署時由 systemd 的 `Environment=` 提供。

| 環境變數 | 預設值 | 說明 |
| --- | --- | --- |
| `SERVER_PORT` | `8080` | HTTP 監聽的 port |
| `APP_ENVIRONMENT` | `local` | `test` / `production` / `local`，決定橫幅顏色與文字 |
| `APP_BUILD_SHA` | `dev` | CI 注入的 git commit SHA |
| `APP_BUILD_TIME` | `unknown` | CI 注入的建置時間 |

對應關係寫在 `src/main/resources/application.yml`：

```yaml
app:
  environment: ${APP_ENVIRONMENT:local}
  build:
    sha: ${APP_BUILD_SHA:dev}
    time: ${APP_BUILD_TIME:unknown}
```

因為是執行期讀取，**同一個 jar** 可以同時部署到 test 與 production，只靠環境變數區分。
`app.version` 則是在建置時由 Maven 從 `pom.xml` 的 `<version>` 填入。

## 部署到 VM

CI 建置出 `target/simpleweb.jar` 後，複製到 VM 上對應的目錄，再重啟 systemd service。
VM 上同時跑兩份，共用同一份程式碼、不同環境變數：

| Service | 環境 | Port | jar 路徑 |
| --- | --- | --- | --- |
| `simpleweb-test` | `test` | 8080 | `/opt/simpleweb/test/simpleweb.jar` |
| `simpleweb-prod` | `production` | 8081 | `/opt/simpleweb/prod/simpleweb.jar` |

Unit 檔大致長這樣（`/etc/systemd/system/simpleweb-test.service`）：

```ini
[Service]
Environment=SERVER_PORT=8080
Environment=APP_ENVIRONMENT=test
EnvironmentFile=-/opt/simpleweb/test/app.env
ExecStart=/usr/bin/java -jar /opt/simpleweb/test/simpleweb.jar
```

部署 workflow 會把 `APP_BUILD_SHA` 與 `APP_BUILD_TIME` 寫入 `app.env`。

部署後的驗證方式：

```bash
curl http://<vm>:8080/actuator/health   # 應為 {"status":"UP", ...}
curl http://<vm>:8080/api/info          # buildSha 應為這次 commit 的 SHA
```

如果 `buildSha` 還是上一次的值，就代表 jar 沒換成功或 service 沒重啟 —— 這是課堂上最常見的狀況。

> 實際的 workflow 與 systemd unit 檔由課程的 `.github/` 內容提供，不在本 README 範圍內。

## 用 Docker 執行（次要）

```powershell
docker build -t simpleweb:latest .
docker run --rm -p 8080:8080 -e APP_ENVIRONMENT=test -e APP_BUILD_SHA=a1b2c3d simpleweb:latest
```

`Dockerfile` 是 multi-stage：build 階段用 `maven:3.9-eclipse-temurin-21`，
執行階段只留 `eclipse-temurin:21-jre` 加上一顆 jar。

## 專案結構

```
.
├── .mvn/wrapper/maven-wrapper.properties
├── mvnw / mvnw.cmd                 # Maven Wrapper（必須一起 commit）
├── pom.xml
├── Dockerfile
└── src
    ├── main
    │   ├── java/money/gh200/simpleweb
    │   │   ├── SimpleWebApplication.java
    │   │   ├── model/AppInfo.java          # 顯示用的資料模型（record）
    │   │   ├── service/InfoService.java    # 組出 AppInfo 的唯一地方
    │   │   └── web/
    │   │       ├── HomeController.java     # GET /
    │   │       └── InfoApiController.java  # GET /api/info
    │   └── resources
    │       ├── application.yml
    │       ├── static/css/site.css
    │       └── templates/index.html
    └── test/java/money/gh200/simpleweb
        ├── SimpleWebApplicationIT.java
        ├── service/InfoServiceTest.java
        └── web/HomeControllerTest.java
```
