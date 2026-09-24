# =============================================================================
#  ESL-MOD -- router port forwarding helper (UPnP)
#
#  Tries to create the UDP port forwarding rule the dedicated server needs,
#  using UPnP on the router.  Many home routers ship with UPnP enabled; if it is
#  switched off, this script says so and you forward the port by hand in the
#  router's web UI (see docs\SERVER.md).
#
#      tools\forward-port.cmd            show the current mapping + external IP
#      tools\forward-port.cmd -Add       create the mapping for the server port
#      tools\forward-port.cmd -Remove    delete it again
#
#  Everything is done through the router's own UPnP service (WANIPConnection),
#  so nothing but the port mapping is touched.
#
#  Usage:
#      powershell -NoProfile -ExecutionPolicy Bypass -File tools\forward-port.ps1 -Add
#      ... -Port 28960 -InternalClient 192.168.31.148 -Description "ESL-MOD server"
# =============================================================================

[CmdletBinding()]
param(
    [int]    $Port = 28960,
    [string] $Protocol = 'UDP',
    [string] $InternalClient = '',
    [string] $Description = 'ESL-MOD server',
    [switch] $Add,
    [switch] $Remove
)

$ErrorActionPreference = 'Stop'

function Get-LocalIPv4 {
    $cfg = Get-NetIPConfiguration | Where-Object { $_.IPv4Address -and $_.IPv4DefaultGateway } |
           Select-Object -First 1
    if ($cfg) { return $cfg.IPv4Address.IPAddress }
    return ''
}

function Find-UpnpGateway {
    # Two search targets on purpose: an IGD answers "InternetGatewayDevice:1",
    # but some routers only reply to the generic "ssdp:all".
    $targets = @(
        'urn:schemas-upnp-org:device:InternetGatewayDevice:1',
        'ssdp:all'
    )

    $locations = @()
    $udp = New-Object System.Net.Sockets.UdpClient
    try {
        $udp.Client.ReceiveTimeout = 1000

        foreach ($st in $targets) {
            $search = @(
                'M-SEARCH * HTTP/1.1',
                'HOST: 239.255.255.250:1900',
                'MAN: "ssdp:discover"',
                'MX: 2',
                ('ST: ' + $st),
                '', ''
            ) -join "`r`n"

            $bytes = [System.Text.Encoding]::ASCII.GetBytes($search)
            [void]$udp.Send($bytes, $bytes.Length, '239.255.255.250', 1900)
        }

        # collect replies for a few seconds; a receive timeout is expected and
        # simply means "nothing left to read right now"
        $deadline = (Get-Date).AddSeconds(5)
        while ((Get-Date) -lt $deadline) {
            try {
                $ep = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
                $resp = [System.Text.Encoding]::ASCII.GetString($udp.Receive([ref]$ep))
                $m = [regex]::Match($resp, 'LOCATION:\s*(\S+)', 'IgnoreCase')
                if ($m.Success) { $locations += $m.Groups[1].Value.Trim() }
            } catch {
                Start-Sleep -Milliseconds 100
            }
        }
    } finally {
        $udp.Close()
    }

    $locations = $locations | Select-Object -Unique
    if (-not $locations) { return $null }

    foreach ($loc in $locations) {
        try {
            $xml = (Invoke-WebRequest -Uri $loc -UseBasicParsing -TimeoutSec 8).Content
        } catch {
            continue
        }

        foreach ($svc in [regex]::Matches($xml, '(?s)<service>(.*?)</service>')) {
            $block = $svc.Groups[1].Value
            $type = [regex]::Match($block, '<serviceType>(.*?)</serviceType>').Groups[1].Value
            if ($type -notmatch 'WAN(IP|PPP)Connection') { continue }

            $ctrl = [regex]::Match($block, '<controlURL>(.*?)</controlURL>').Groups[1].Value
            if (-not $ctrl) { continue }

            if ($ctrl.StartsWith('/')) {
                $base = [uri]$loc
                $ctrl = $base.Scheme + '://' + $base.Authority + $ctrl
            } elseif ($ctrl -notmatch '^https?://') {
                $ctrl = ([uri]::new([uri]$loc, $ctrl)).AbsoluteUri
            }

            return [pscustomobject]@{
                ServiceType = $type.Trim()
                ControlUrl  = $ctrl
            }
        }
    }

    return $null
}

function Invoke-UpnpAction {
    param($Gateway, [string] $Action, [string] $Body)

    $env = @"
<?xml version="1.0"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
<s:Body>$Body</s:Body>
</s:Envelope>
"@

    $headers = @{
        'SOAPAction'   = '"' + $Gateway.ServiceType + '#' + $Action + '"'
        'Content-Type' = 'text/xml; charset="utf-8"'
    }

    $resp = Invoke-WebRequest -Uri $Gateway.ControlUrl -Method Post -Headers $headers `
                              -Body $env -ContentType 'text/xml; charset="utf-8"' `
                              -UseBasicParsing -TimeoutSec 10

    return $resp.Content
}

# -----------------------------------------------------------------------------

$gateway = Find-UpnpGateway

if (-not $gateway) {
    Write-Output 'UPnP: no gateway found (UPnP is probably switched off on the router).'
    Write-Output ''
    Write-Output ('Forward UDP ' + $Port + ' by hand instead:')
    Write-Output '  1. open the router web UI (its address is the default gateway, e.g. 192.168.31.1)'
    Write-Output ('  2. add a port forwarding rule: UDP ' + $Port + ' -> this PC''s LAN IP, port ' + $Port)
    Write-Output '  3. docs\SERVER.md has the step by step version'
    exit 1
}

Write-Output ('UPnP gateway : ' + $gateway.ControlUrl)

$ns = $gateway.ServiceType.Substring(0, $gateway.ServiceType.LastIndexOf(':'))
$prefix = $gateway.ServiceType.Substring($gateway.ServiceType.LastIndexOf(':') + 1)

# --- who we are ---------------------------------------------------------------
if (-not $InternalClient) { $InternalClient = Get-LocalIPv4 }
if (-not $InternalClient) { throw 'Could not determine this PC''s LAN IPv4 - pass -InternalClient <ip>' }

Write-Output ('this PC      : ' + $InternalClient)
Write-Output ('mapping      : ' + $Protocol + ' ' + $Port + ' -> ' + $InternalClient + ':' + $Port)

# --- external address as the router sees it -----------------------------------
try {
    $body = '<u:GetExternalIPAddress xmlns:u="' + $gateway.ServiceType + '"/>'
    $text = Invoke-UpnpAction -Gateway $gateway -Action 'GetExternalIPAddress' -Body $body
    $ext = [regex]::Match($text, '<NewExternalIPAddress>(.*?)</NewExternalIPAddress>').Groups[1].Value
    if ($ext) { Write-Output ('router WAN IP: ' + $ext) }
} catch {
    Write-Output ('router WAN IP: (query failed: ' + $_.Exception.Message + ')')
}

# --- current mapping ---------------------------------------------------------
$existing = ''
try {
    $body = '<u:GetSpecificPortMappingEntry xmlns:u="' + $gateway.ServiceType + '">' +
            '<NewRemoteHost></NewRemoteHost>' +
            '<NewExternalPort>' + $Port + '</NewExternalPort>' +
            '<NewProtocol>' + $Protocol + '</NewProtocol>' +
            '</u:GetSpecificPortMappingEntry>'
    $text = Invoke-UpnpAction -Gateway $gateway -Action 'GetSpecificPortMappingEntry' -Body $body
    $existing = [regex]::Match($text, '<NewInternalClient>(.*?)</NewInternalClient>').Groups[1].Value
    if ($existing) { Write-Output ('current rule : already forwarded to ' + $existing) }
    else { Write-Output 'current rule : none' }
} catch {
    Write-Output 'current rule : none'
}

if ($Remove) {
    if (-not $existing) { Write-Output 'nothing to remove'; exit 0 }

    $body = '<u:DeletePortMapping xmlns:u="' + $gateway.ServiceType + '">' +
            '<NewRemoteHost></NewRemoteHost>' +
            '<NewExternalPort>' + $Port + '</NewExternalPort>' +
            '<NewProtocol>' + $Protocol + '</NewProtocol>' +
            '</u:DeletePortMapping>'
    Invoke-UpnpAction -Gateway $gateway -Action 'DeletePortMapping' -Body $body | Out-Null
    Write-Output ('removed the UDP ' + $Port + ' forward')
    exit 0
}

if (-not $Add) {
    Write-Output ''
    Write-Output 'Nothing changed - run again with -Add to create the forward.'
    exit 0
}

# --- add / refresh ------------------------------------------------------------
$body = '<u:AddPortMapping xmlns:u="' + $gateway.ServiceType + '">' +
        '<NewRemoteHost></NewRemoteHost>' +
        '<NewExternalPort>' + $Port + '</NewExternalPort>' +
        '<NewProtocol>' + $Protocol + '</NewProtocol>' +
        '<NewInternalPort>' + $Port + '</NewInternalPort>' +
        '<NewInternalClient>' + $InternalClient + '</NewInternalClient>' +
        '<NewEnabled>1</NewEnabled>' +
        '<NewPortMappingDescription>' + $Description + '</NewPortMappingDescription>' +
        '<NewLeaseDuration>0</NewLeaseDuration>' +
        '</u:AddPortMapping>'

Invoke-UpnpAction -Gateway $gateway -Action 'AddPortMapping' -Body $body | Out-Null

Write-Output ''
Write-Output ('forward created: ' + $Protocol + ' ' + $Port + ' -> ' + $InternalClient + ':' + $Port)
Write-Output 'Friends can now join with the router WAN IP above (and the server is listed in the IW4x browser).'
