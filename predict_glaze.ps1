param(
    [Parameter(Mandatory = $true)][string]$RequestPath,
    [Parameter(Mandatory = $true)][string]$ResponsePath
)

$ErrorActionPreference = 'Stop'
try {
    $url = $env:GLAZE_API_URL
    if ([string]::IsNullOrWhiteSpace($url)) {
        $url = 'https://viewpicture-curriculum-examines-someone.trycloudflare.com/api/glaze/prediction'
    }
    $endpoint = $null
    if (![uri]::TryCreate($url.Trim(), [UriKind]::Absolute, [ref]$endpoint) -or
        $endpoint.UserInfo -or ($endpoint.Scheme -ne 'https' -and
        !($endpoint.IsLoopback -and $endpoint.Scheme -eq 'http'))) {
        throw 'Set GLAZE_API_URL to the current HTTPS prediction endpoint or a local HTTP endpoint.'
    }

    $headers = @{ Accept = 'application/json' }
    if (![string]::IsNullOrWhiteSpace($env:GLAZE_API_TOKEN)) {
        $headers.Authorization = 'Bearer ' + $env:GLAZE_API_TOKEN.Trim()
    }
    $body = [IO.File]::ReadAllText($RequestPath)
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    try {
        $prediction = Invoke-RestMethod -Method Post -Uri $endpoint -Headers $headers `
            -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body)) `
            -MaximumRedirection 0 -TimeoutSec 35
    } catch {
        $statusCode = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode }
        switch ($statusCode) {
            { $_ -in @(401, 403) } { throw 'The prediction API denied access. Check GLAZE_API_TOKEN.' }
            422 { throw 'The prediction API rejected these glaze inputs. Check the API request schema and glaze IDs.' }
            { $_ -ge 300 } { throw "The prediction API returned HTTP $statusCode. Check the endpoint and try again." }
            default { throw 'Could not reach the prediction API. Check GLAZE_API_URL and the connection.' }
        }
    }
    [IO.File]::WriteAllText($ResponsePath, (ConvertTo-Json -InputObject $prediction -Depth 30))
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
