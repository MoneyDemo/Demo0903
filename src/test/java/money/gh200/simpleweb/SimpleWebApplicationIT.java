package money.gh200.simpleweb;

import java.util.Map;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.http.HttpStatus;
import org.springframework.web.client.RestClient;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Starts the real application on a random port (never a fixed one, so it can run
 * on a build agent that is already using 8080) and calls it over HTTP.
 */
@SpringBootTest(
        webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = {
                "app.environment=test",
                "app.build.sha=deadbee",
                "app.build.time=2026-09-03T00:10:00Z"
        })
class SimpleWebApplicationIT {

    @LocalServerPort
    private int port;

    private RestClient client() {
        return RestClient.create("http://localhost:" + port);
    }

    @Test
    @DisplayName("/api/info 回傳這次部署的完整資訊")
    void infoEndpointReturnsTheDeployedBuildMetadata() {
        var response = client().get().uri("/api/info").retrieve()
                .toEntity(new ParameterizedTypeReference<Map<String, String>>() {});

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);

        Map<String, String> body = response.getBody();
        assertThat(body).isNotNull();
        assertThat(body).containsEntry("application", "SimpleWeb")
                .containsEntry("version", "1.0.0")
                .containsEntry("environment", "test")
                .containsEntry("buildSha", "deadbee")
                .containsEntry("buildTime", "2026-09-03T00:10:00Z");
        assertThat(body.get("hostname")).isNotBlank();
        assertThat(body.get("javaVersion")).startsWith("21");
        assertThat(body.get("serverTime")).isNotBlank();
    }

    @Test
    @DisplayName("/ 回傳 HTML 首頁並帶有藍色 test 橫幅")
    void homePageIsServedWithTheTestBanner() {
        var response = client().get().uri("/").retrieve().toEntity(String.class);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).contains("TEST").contains("env-test").contains("deadbee");
    }

    @Test
    @DisplayName("/actuator/health 回報 UP")
    void healthEndpointReportsUp() {
        var response = client().get().uri("/actuator/health").retrieve()
                .toEntity(new ParameterizedTypeReference<Map<String, Object>>() {});

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).containsEntry("status", "UP");
    }
}
