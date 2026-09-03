package money.gh200.simpleweb.model;

/**
 * Everything the demo page and {@code /api/info} show. One immutable snapshot per request.
 */
public record AppInfo(
        String application,
        String version,
        String environment,
        String buildSha,
        String buildTime,
        String hostname,
        String javaVersion,
        String serverTime) {
}
