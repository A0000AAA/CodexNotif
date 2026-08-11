using System.Net.Http;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using AgentPager.Models;

namespace AgentPager.Services;

public sealed class RelayApiClient : IDisposable
{
    public RelayApiClient(string serverBaseUrl)
        : this(
            serverBaseUrl,
            ServerAccessKeyResolver.ReadOptional())
    {
    }

    public RelayApiClient(
        string serverBaseUrl,
        string? accessKey,
        HttpMessageHandler? handler = null)
    {
        ServerBaseUrl = ServerAddressResolver.Normalize(serverBaseUrl);
        _accessKey = accessKey;
        _httpClient = handler is null
            ? new HttpClient()
            : new HttpClient(handler, disposeHandler: true);
        _httpClient.Timeout = TimeSpan.FromSeconds(20);
    }

    public string ServerBaseUrl { get; }
    public bool HasValidAccessKey =>
        ServerAccessKeyResolver.IsValid(_accessKey);

    private readonly string? _accessKey;
    private readonly HttpClient _httpClient;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    public async Task<bool> HealthAsync(
        CancellationToken cancellationToken = default)
    {
        using var request = CreateRequest(HttpMethod.Get, "/health");
        using var response = await _httpClient.SendAsync(
            request,
            cancellationToken);

        if (!response.IsSuccessStatusCode)
            return false;

        var health = await response.Content.ReadFromJsonAsync<HealthResponse>(
            JsonOptions,
            cancellationToken);

        return health?.Ok == true;
    }

    public async Task<BindCreateResponse> CreateBindingAsync(
        string deviceId,
        string email,
        string? currentDeviceToken,
        CancellationToken cancellationToken = default)
    {
        using var request = CreateRequest(
            HttpMethod.Post,
            "/api/v1/bind/create",
            currentDeviceToken);

        request.Content = JsonContent.Create(new
        {
            deviceId,
            email
        });

        using var response = await _httpClient.SendAsync(
            request,
            cancellationToken);

        await EnsureSuccessAsync(
            response,
            cancellationToken);

        return await response.Content.ReadFromJsonAsync<BindCreateResponse>(
                   JsonOptions,
                   cancellationToken)
               ?? throw new InvalidOperationException(
                   "服务器没有返回有效的绑定信息。");
    }

    public async Task<BindStatusResponse> GetBindingStatusAsync(
        string bindId,
        string pollToken,
        CancellationToken cancellationToken = default)
    {
        var url =
            ServerBaseUrl
            + "/api/v1/bind/"
            + Uri.EscapeDataString(bindId)
            + "?pollToken="
            + Uri.EscapeDataString(pollToken);

        using var request = CreateRequest(HttpMethod.Get, url);
        using var response = await _httpClient.SendAsync(
            request,
            cancellationToken);

        await EnsureSuccessAsync(
            response,
            cancellationToken);

        return await response.Content.ReadFromJsonAsync<BindStatusResponse>(
                   JsonOptions,
                   cancellationToken)
               ?? throw new InvalidOperationException(
                   "服务器没有返回有效的绑定状态。");
    }

    public async Task SendEventAsync(
        AgentEvent e,
        string deviceToken,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(deviceToken))
            throw new InvalidOperationException(
                "当前设备尚未绑定邮箱。");

        using var request = CreateRequest(
            HttpMethod.Post,
            "/api/v1/events",
            deviceToken);

        request.Content = JsonContent.Create(new
        {
            deviceId = e.DeviceId,
            source = e.Source,
            @event = e.EventType,
            timestamp = e.Timestamp
        });

        using var response = await _httpClient.SendAsync(
            request,
            cancellationToken);

        await EnsureSuccessAsync(
            response,
            cancellationToken);
    }

    public async Task<AuthCheckResponse> CheckAuthenticationAsync(
        string deviceId,
        string? deviceToken,
        CancellationToken cancellationToken = default)
    {
        var path = "/api/v1/auth/check?deviceId="
                   + Uri.EscapeDataString(deviceId);
        using var request = CreateRequest(
            HttpMethod.Get,
            path,
            deviceToken);
        using var response = await _httpClient.SendAsync(
            request,
            cancellationToken);

        await EnsureSuccessAsync(response, cancellationToken);

        return await response.Content.ReadFromJsonAsync<AuthCheckResponse>(
                   JsonOptions,
                   cancellationToken)
               ?? throw new InvalidOperationException(
                   "服务器没有返回有效的认证状态。");
    }

    private HttpRequestMessage CreateRequest(
        HttpMethod method,
        string pathOrUrl,
        string? deviceToken = null)
    {
        string accessKey = ServerAccessKeyResolver.Validate(_accessKey);
        string url = Uri.IsWellFormedUriString(
            pathOrUrl,
            UriKind.Absolute)
            ? pathOrUrl
            : ServerBaseUrl + pathOrUrl;
        var request = new HttpRequestMessage(method, url);
        request.Headers.Add(ServerAccessKeyResolver.HeaderName, accessKey);

        if (!string.IsNullOrWhiteSpace(deviceToken))
        {
            request.Headers.Authorization =
                new AuthenticationHeaderValue("Bearer", deviceToken);
        }

        return request;
    }

    private static async Task EnsureSuccessAsync(
        HttpResponseMessage response,
        CancellationToken cancellationToken)
    {
        if (response.IsSuccessStatusCode)
            return;

        string message =
            $"服务器返回 HTTP {(int)response.StatusCode}";

        try
        {
            var api = await response.Content.ReadFromJsonAsync<ApiResponse>(
                JsonOptions,
                cancellationToken);

            if (!string.IsNullOrWhiteSpace(api?.Message))
                message = api.Message;
        }
        catch
        {
            // 保留 HTTP 错误作为回退信息。
        }

        throw new InvalidOperationException(message);
    }

    public void Dispose()
    {
        _httpClient.Dispose();
    }
}
