param(
    [Parameter(Mandatory = $true)][string]$RequestPath,
    [Parameter(Mandatory = $true)][string]$ResponsePath
)

$ErrorActionPreference = 'Stop'
try {
    $apiKey = $env:NOVA_OPENROUTER_API_KEY
    if ([string]::IsNullOrWhiteSpace($apiKey)) { throw 'No API key was provided to the assistant process.' }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $request = Get-Content -LiteralPath $RequestPath -Raw -Encoding UTF8 | ConvertFrom-Json

    function Get-NullableEnumSchema($values) {
        return @{ anyOf = @(@{ type = 'string'; enum = $values }, @{ type = 'null' }) }
    }
    $nullableString = @{ type = @('string', 'null') }
    $nullableNumber = @{ type = @('number', 'null') }
    $properties = [ordered]@{
        reply = @{ type = 'string' }
        changes = @{
            type = 'object'
            additionalProperties = $false
            properties = [ordered]@{
                model_id = Get-NullableEnumSchema @('BOWL', 'VASE', 'CUP')
                glaze_id = Get-NullableEnumSchema @('CELADON', 'COBALT', 'OATMEAL', 'CUSTOM')
                custom_color_srgb = $nullableString
                recipe_id_or_composition = $nullableString
                nominal_thickness_mm = $nullableNumber
                peak_temperature_C = $nullableNumber
                atmosphere = Get-NullableEnumSchema @('oxidation', 'neutral', 'reduction', 'unspecified')
                atmosphere_notes = $nullableString
                cone = $nullableString
                heat_up_rate_C_per_hour = $nullableNumber
                peak_soak_minutes = $nullableNumber
                firing_schedule = $nullableString
                cooling_rate_C_per_hour = $nullableNumber
                cooling_profile = $nullableString
                clay_body = $nullableString
                fired_clay_color_srgb = $nullableString
                thickness_map_path = $nullableString
                firing_geometry_notes = $nullableString
                clear_fields = @{
                    type = 'array'
                    items = @{ type = 'string'; enum = @(
                        'recipe_id_or_composition', 'nominal_thickness_mm', 'peak_temperature_C',
                        'atmosphere_notes', 'cone', 'heat_up_rate_C_per_hour', 'peak_soak_minutes',
                        'firing_schedule', 'cooling_rate_C_per_hour', 'cooling_profile', 'clay_body',
                        'fired_clay_color_srgb', 'thickness_map_path', 'firing_geometry_notes'
                    ) }
                }
            }
            required = @(
                'model_id', 'glaze_id', 'custom_color_srgb', 'recipe_id_or_composition',
                'nominal_thickness_mm', 'peak_temperature_C', 'atmosphere', 'atmosphere_notes',
                'cone', 'heat_up_rate_C_per_hour', 'peak_soak_minutes', 'firing_schedule',
                'cooling_rate_C_per_hour', 'cooling_profile', 'clay_body', 'fired_clay_color_srgb',
                'thickness_map_path', 'firing_geometry_notes', 'clear_fields'
            )
        }
    }
    $schema = @{
        type = 'object'
        additionalProperties = $false
        properties = $properties
        required = @('reply', 'changes')
    }
    $body = @{
        model = 'openai/gpt-4o-mini'
        messages = @($request.messages)
        temperature = 0.2
        max_tokens = 700
        store = $false
        provider = @{ require_parameters = $true }
        response_format = @{
            type = 'json_schema'
            json_schema = @{ name = 'nova_assistant_response'; strict = $true; schema = $schema }
        }
    } | ConvertTo-Json -Depth 20

    $response = Invoke-RestMethod -Method Post -Uri 'https://openrouter.ai/api/v1/chat/completions' `
        -Headers @{ Authorization = "Bearer $apiKey"; 'HTTP-Referer' = 'https://nova-pottery.local'; 'X-Title' = 'NOVA Pottery Studio' } `
        -ContentType 'application/json' -Body $body -TimeoutSec 75
    $content = $response.choices[0].message.content
    if ([string]::IsNullOrWhiteSpace($content)) { throw 'The assistant returned no message.' }
    $result = $content | ConvertFrom-Json
    $encoded = $result | ConvertTo-Json -Depth 10
    [IO.File]::WriteAllText($ResponsePath, $encoded, [Text.UTF8Encoding]::new($false))
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
