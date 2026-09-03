package money.gh200.simpleweb.web;

import money.gh200.simpleweb.model.AppInfo;
import money.gh200.simpleweb.service.InfoService;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class InfoApiController {

    private final InfoService infoService;

    public InfoApiController(InfoService infoService) {
        this.infoService = infoService;
    }

    @GetMapping("/api/info")
    public AppInfo info() {
        return infoService.currentInfo();
    }
}
