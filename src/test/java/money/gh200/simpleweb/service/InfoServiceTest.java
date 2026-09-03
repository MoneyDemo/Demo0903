package money.gh200.simpleweb.service;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneId;

import money.gh200.simpleweb.model.AppInfo;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;

import static org.assertj.core.api.Assertions.assertThat;

class InfoServiceTest {

    private static final Clock FIXED_CLOCK =
            Clock.fixed(Instant.parse("2026-09-03T01:23:45Z"), ZoneId.of("UTC"));

    private static InfoService serviceWith(String environment, String buildSha, String buildTime) {
        return new InfoService("SimpleWeb", "1.0.0", environment, buildSha, buildTime,
                FIXED_CLOCK, () -> "gh200-vm");
    }

    @Test
    @DisplayName("回傳 CI 注入的建置資訊")
    void exposesTheBuildMetadataInjectedByCi() {
        AppInfo info = serviceWith("production", "a1b2c3d", "2026-09-03T00:10:00Z").currentInfo();

        assertThat(info.application()).isEqualTo("SimpleWeb");
        assertThat(info.version()).isEqualTo("1.0.0");
        assertThat(info.environment()).isEqualTo("production");
        assertThat(info.buildSha()).isEqualTo("a1b2c3d");
        assertThat(info.buildTime()).isEqualTo("2026-09-03T00:10:00Z");
        assertThat(info.hostname()).isEqualTo("gh200-vm");
        assertThat(info.javaVersion()).isEqualTo(System.getProperty("java.version"));
        assertThat(info.serverTime()).isEqualTo("2026-09-03 01:23:45 UTC");
    }

    @ParameterizedTest(name = "APP_ENVIRONMENT=\"{0}\" -> {1}")
    @CsvSource({
            "test,          test",
            "  TEST  ,      test",
            "Production,    production",
            "local,         local",
            "staging,       local",
            "'',            local"
    })
    @DisplayName("環境名稱正規化，未知的值一律當成 local")
    void normalizesEnvironmentAndFallsBackToLocal(String rawEnvironment, String expected) {
        assertThat(serviceWith(rawEnvironment, "sha", "time").environment()).isEqualTo(expected);
    }

    @Test
    @DisplayName("環境變數沒設定時使用預設值")
    void usesDefaultsWhenEnvironmentVariablesAreMissing() {
        AppInfo info = serviceWith(null, null, "   ").currentInfo();

        assertThat(info.environment()).isEqualTo(InfoService.DEFAULT_ENVIRONMENT);
        assertThat(info.buildSha()).isEqualTo(InfoService.DEFAULT_BUILD_SHA);
        assertThat(info.buildTime()).isEqualTo(InfoService.DEFAULT_BUILD_TIME);
    }

    @ParameterizedTest(name = "{0} -> {1}")
    @CsvSource({
            "test,       env-test",
            "production, env-production",
            "local,      env-local",
            "whatever,   env-local"
    })
    @DisplayName("每個環境對應到自己的橫幅顏色")
    void mapsEachEnvironmentToItsOwnBannerColour(String environment, String expectedCssClass) {
        assertThat(serviceWith(environment, "sha", "time").bannerClass()).isEqualTo(expectedCssClass);
    }

    @Test
    @DisplayName("主機名稱查不到時不會讓頁面爆掉")
    void survivesAHostnameLookupFailure() {
        InfoService service = new InfoService("SimpleWeb", "1.0.0", "test", "sha", "time",
                FIXED_CLOCK, () -> {
                    throw new IllegalStateException("no DNS on this box");
                });

        assertThat(service.currentInfo().hostname()).isEqualTo(InfoService.UNKNOWN_HOSTNAME);
    }
}
