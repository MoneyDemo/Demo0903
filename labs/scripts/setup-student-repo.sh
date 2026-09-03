#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# GH-200 學員環境快速設定（Linux / macOS）
#
# 這個腳本會：
#   1. 檢查前置工具：git / gh / java (>= 21)
#   2. 檢查 gh 是否已登入
#   3. 把課程 repo fork 到你自己的帳號（已存在就沿用），並 clone 到本機
#   4. 在你的 fork 上啟用 GitHub Actions
#   5. 檢查 repo 可見度（Lab 04/05 需要 public 才能讓 VM 匿名下載 release asset）
#   6. 建立 test 與 production 兩個 environment
#   7. （選用）設定 Azure OIDC secrets 與 VM variables
#   8. 印出下一步
#
# 安全性：不刪除任何檔案、不使用萬用字元、不覆寫既有目錄、不硬編 token。
#
# 用法：
#   ./setup-student-repo.sh
#   VM_PUBLIC_IP=<VM_PUBLIC_IP> AZURE_RESOURCE_GROUP=<RG> AZURE_VM_NAME=<VM> \
#     ./setup-student-repo.sh
# ---------------------------------------------------------------------------
set -euo pipefail

UPSTREAM_REPO="${UPSTREAM_REPO:-MoneyDemo/20260903-GH200}"
TARGET_DIR="${TARGET_DIR:-$HOME/gh200}"

# 選用（講師在課堂上公布後再填）
VM_PUBLIC_IP="${VM_PUBLIC_IP:-}"
AZURE_RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-}"
AZURE_VM_NAME="${AZURE_VM_NAME:-}"
AZURE_CLIENT_ID="${AZURE_CLIENT_ID:-}"
AZURE_TENANT_ID="${AZURE_TENANT_ID:-}"
AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:-}"

C_CYAN=$'\033[36m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_OFF=$'\033[0m'
step() { printf '\n%s==> %s%s\n' "$C_CYAN" "$1" "$C_OFF"; }
ok()   { printf '    %s[OK]%s %s\n' "$C_GREEN" "$C_OFF" "$1"; }
warn() { printf '    %s[!]%s  %s\n' "$C_YELLOW" "$C_OFF" "$1"; }
die()  { printf '\n[ERROR] %s\n' "$1" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 1. 前置工具檢查
# ---------------------------------------------------------------------------
step "檢查前置工具"

for tool in git gh java; do
  command -v "$tool" >/dev/null 2>&1 || die "找不到 '$tool'，請先安裝（gh = GitHub CLI）。"
  ok "$tool 已安裝"
done

java_raw="$(java -version 2>&1 || true)"
java_major="$(printf '%s\n' "$java_raw" | sed -n 's/.*version "\([0-9]*\).*/\1/p' | head -n 1)"
[ -n "$java_major" ] || die "無法判讀 java 版本，輸出如下：
$java_raw"
[ "$java_major" -ge 21 ] || die "需要 Java 21 或以上，目前偵測到 $java_major。請安裝 JDK 21（建議 Temurin）。"
ok "Java $java_major（>= 21）"

echo "    注意：本課程使用 Maven Wrapper，不需要安裝 Maven。"
echo "          本機建置指令為 ./mvnw -B verify"

# ---------------------------------------------------------------------------
# 2. gh 登入狀態
# ---------------------------------------------------------------------------
step "檢查 GitHub CLI 登入狀態"

gh auth status || die "gh 尚未登入。請先執行： gh auth login"
ok "gh 已登入"

ME="$(gh api user --jq '.login')"
[ -n "$ME" ] || die "無法取得 GitHub 帳號名稱。"
ok "GitHub 帳號：$ME"

REPO_NAME="${UPSTREAM_REPO##*/}"
MY_REPO="$ME/$REPO_NAME"

# ---------------------------------------------------------------------------
# 3. Fork（已存在則沿用）
# ---------------------------------------------------------------------------
step "準備你自己的 repo：$MY_REPO"

if gh repo view "$MY_REPO" --json name >/dev/null 2>&1; then
  IS_FORK="$(gh repo view "$MY_REPO" --json isFork --jq '.isFork')"
  PARENT="$(gh repo view "$MY_REPO" --json parent --jq '.parent.nameWithOwner // ""')"
  if [ "$IS_FORK" != "true" ] || [ "$PARENT" != "$UPSTREAM_REPO" ]; then
    die "$MY_REPO 已存在，但不是 $UPSTREAM_REPO 的 fork；為避免修改無關 repo，腳本停止。"
  fi
  ok "$MY_REPO 已存在且已確認是 $UPSTREAM_REPO 的 fork"
else
  echo "    fork $UPSTREAM_REPO ..."
  gh repo fork "$UPSTREAM_REPO" --clone=false --remote=false \
    || die "fork 失敗，請確認你對 $UPSTREAM_REPO 有讀取權限。"

  ready=0
  for i in $(seq 1 15); do
    sleep 2
    if gh repo view "$MY_REPO" --json name >/dev/null 2>&1; then ready=1; break; fi
    echo "    等待 fork 完成... ($i/15)"
  done
  [ "$ready" -eq 1 ] || die "fork 似乎尚未完成，請稍後再執行一次本腳本。"
  ok "已建立 $MY_REPO"
fi

# ---------------------------------------------------------------------------
# 4. Clone
# ---------------------------------------------------------------------------
step "Clone 到本機"

mkdir -p "$TARGET_DIR"
CLONE_PATH="$TARGET_DIR/$REPO_NAME"

if [ -e "$CLONE_PATH" ]; then
  warn "$CLONE_PATH 已存在，跳過 clone（腳本不會覆寫既有目錄）"
else
  gh repo clone "$MY_REPO" "$CLONE_PATH" || die "clone 失敗。"
  ok "已 clone 到 $CLONE_PATH"
fi

# ---------------------------------------------------------------------------
# 5. 啟用 Actions
# ---------------------------------------------------------------------------
step "啟用 GitHub Actions"

gh api --method PUT "repos/$MY_REPO/actions/permissions" \
  -H "Accept: application/vnd.github+json" \
  -F enabled=true >/dev/null \
  || die "Actions 啟用失敗，請確認你對該 repo 有 admin 權限。"
ok "Actions 已啟用（保留既有 allowed-actions policy）"

# ---------------------------------------------------------------------------
# 5b. 可見度檢查（Lab04/05 需要 public 才能讓 VM 匿名下載 release asset）
# ---------------------------------------------------------------------------
step "檢查 repo 可見度"

IS_PRIVATE="$(gh repo view "$MY_REPO" --json isPrivate --jq '.isPrivate')"
if [ "$IS_PRIVATE" = "true" ]; then
  warn "$MY_REPO 目前是 private。"
  warn "Lab 04／05 的 VM 需要「匿名」下載 build-<commit-sha> 的 release asset，"
  warn "請把 repo 改成 public，或改用 Lab 04 附錄的 SSH 變體。"
  warn "（本腳本不會替你更動可見度，請自行到 repo 設定頁調整。）"
else
  ok "repo 為 public，VM 可匿名下載 release asset"
fi

# ---------------------------------------------------------------------------
# 6. 建立 environments
# ---------------------------------------------------------------------------
step "建立 environments：test / production"

for env_name in test production; do
  gh api --method PUT "repos/$MY_REPO/environments/$env_name" \
    -H "Accept: application/vnd.github+json" >/dev/null \
    || die "建立 environment '$env_name' 失敗。"
  ok "environment '$env_name' 就緒"
done
warn "production 的 required reviewer 需要你自己在 repo 設定頁加上（Lab 05 會用到）"

# ---------------------------------------------------------------------------
# 7. 選用：secrets 與 variables
# ---------------------------------------------------------------------------
step "設定 secrets 與 variables（沒填的會跳過）"

set_secret() {
  local name="$1" value="$2"
  if [ -z "$value" ]; then warn "secret $name 未提供，跳過"; return 0; fi
  printf '%s' "$value" | gh secret set "$name" --repo "$MY_REPO" \
    || die "設定 secret $name 失敗。"
  ok "secret $name 已設定"
}

set_variable() {
  local name="$1" value="$2"
  if [ -z "$value" ]; then warn "variable $name 未提供，跳過"; return 0; fi
  gh variable set "$name" --repo "$MY_REPO" --body "$value" \
    || die "設定 variable $name 失敗。"
  ok "variable $name = $value"
}

set_secret   AZURE_CLIENT_ID       "$AZURE_CLIENT_ID"
set_secret   AZURE_TENANT_ID       "$AZURE_TENANT_ID"
set_secret   AZURE_SUBSCRIPTION_ID "$AZURE_SUBSCRIPTION_ID"
set_variable VM_PUBLIC_IP          "$VM_PUBLIC_IP"
set_variable AZURE_RESOURCE_GROUP  "$AZURE_RESOURCE_GROUP"
set_variable AZURE_VM_NAME         "$AZURE_VM_NAME"

if [ -n "$AZURE_CLIENT_ID$AZURE_TENANT_ID$AZURE_SUBSCRIPTION_ID" ]; then
  warn "設定 Azure IDs 不會自動建立 OIDC trust。講師仍須為這個 fork 建立專屬 federated credential 與 RBAC。"
fi

# ---------------------------------------------------------------------------
# 8. 下一步
# ---------------------------------------------------------------------------
step "完成！接下來要做的事"

cat <<EOF
  你的 repo   : https://github.com/$MY_REPO
  本機路徑    : $CLONE_PATH

  1. cd "$CLONE_PATH"
  2. 本機先試跑一次建置（不需要安裝 Maven）：
         ./mvnw -B verify
     成功後應該會產生 target/simpleweb.jar
  3. 打開 labs/README.md，從 Lab 01 開始
  4. 講師確認你的 fork 已有專屬 OIDC federated credential 與 RBAC 後，
     才設定 Azure secrets／variables。只有 VM public IP 不代表你已取得 Azure 權限。
         gh variable set VM_PUBLIC_IP         --repo $MY_REPO --body "<VM_PUBLIC_IP>"
         gh variable set AZURE_RESOURCE_GROUP --repo $MY_REPO --body "<RG>"
         gh variable set AZURE_VM_NAME        --repo $MY_REPO --body "<VM>"
  5. Lab 05 之前，記得到 repo 設定 > Environments > production
     加上 required reviewer（把你自己加進去即可）
  6. Lab 04／05 預設由講師在 class repo 實跑；fork 若沒有專屬 OIDC trust，
     你仍要完成 YAML，但不要共用講師的私鑰或長期 client secret。
EOF
