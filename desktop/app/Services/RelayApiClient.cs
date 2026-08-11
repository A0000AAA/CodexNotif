using System.Net.Http;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using AgentPager.Models;

namespace AgentPager.Services;

public sealed class RelayApiClient : IDisposable
{
    public RelayApiClient()
        : this(ServerAddressResolver.Resolve(null).BaseUrl)
    {
    }

    public RelayApiClient(string serverBaseUrl)
    {
        ServerBaseUrl = ServerAddressResolver.Normalize(serverBaseUrl);
    }

    public string ServerBaseUrl { get; }

    private readonly HttpClient _httpClient = new()
    {
        Timeout = TimeSpan.FromSeconds(20)
    };

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    public async Task<bool> HealthAsync(
        CancellationToken cancellationToken = default)
    {
        using var response = await _httpClient.GetAsync(
            ServerBaseUrl + "/health",
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
        using var request = new HttpRequestMessage(
            HttpMethod.Post,
            ServerBaseUrl + "/api/v1/bind/create");

        if (!string.IsNullOrWhiteSpace(currentDeviceToken))
        {
            request.Headers.Authorization =
                new AuthenticationHeaderValue(
                    "Bearer",
                    currentDeviceToken);
        }

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

        using var response = await _httpClient.GetAsync(
            url,
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

        using var request = new HttpRequestMessage(
            HttpMethod.Post,
            ServerBaseUrl + "/api/v1/events");

        request.Headers.Authorization =
            new AuthenticationHeaderValue(
                "Bearer",
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
