package money.gh200.simpleweb.web;

import money.gh200.simpleweb.service.InfoService;

import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;

@Controller
public class HomeController {

    private final InfoService infoService;

    public HomeController(InfoService infoService) {
        this.infoService = infoService;
    }

    @GetMapping("/")
    public String index(Model model) {
        model.addAttribute("info", infoService.currentInfo());
        model.addAttribute("bannerClass", infoService.bannerClass());
        return "index";
    }
}
