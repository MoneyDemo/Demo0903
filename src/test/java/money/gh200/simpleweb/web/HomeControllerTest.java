package money.gh200.simpleweb.web;

import money.gh200.simpleweb.service.InfoService;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;

import static org.hamcrest.Matchers.containsString;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.view;

@WebMvcTest(HomeController.class)
@Import(InfoService.class)
@TestPropertySource(properties = {
        "app.environment=test",
        "app.build.sha=abc1234",
        "app.build.time=2026-09-03T00:10:00Z"
})
class HomeControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Test
    @DisplayName("首頁回 200 並顯示環境名稱與建置資訊")
    void homePageShowsTheEnvironmentAndBuildInformation() throws Exception {
        mockMvc.perform(get("/"))
                .andExpect(status().isOk())
                .andExpect(view().name("index"))
                .andExpect(content().string(containsString("TEST")))
                .andExpect(content().string(containsString("env-test")))
                .andExpect(content().string(containsString("abc1234")))
                .andExpect(content().string(containsString("2026-09-03T00:10:00Z")));
    }
}
