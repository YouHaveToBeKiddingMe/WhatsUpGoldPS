<#
.SYNOPSIS
Connects to a WhatsUp Gold (WUG) server and obtains an OAuth 2.0 authorization token.

.DESCRIPTION
The Connect-WUGServer function establishes a connection to a WhatsUp Gold server using the specified parameters,
and obtains an authorization token using the OAuth 2.0 password grant type flow. The function validates the
input parameters and handles credential input, and also allows for ignoring SSL certificate validation errors.
The authorization token is stored in a global variable for subsequent API requests.

.PARAMETER serverUri
The URI of the WhatsUp Gold server to connect to.

.PARAMETER Protocol
The protocol to use for the connection (http or https). Default is http.

.PARAMETER Username
The username to use for authentication. If not provided, the function will prompt for it.

.PARAMETER Password
The password to use for authentication. If not provided, the function will prompt for it.

.PARAMETER Credential
A PSCredential object containing the username and password for authentication.

.PARAMETER TokenEndpoint
The endpoint for obtaining the OAuth 2.0 authorization token. Default is "/api/v1/token".

.PARAMETER Port
The TCPIP port to use for the connection. Default is 9644.

.PARAMETER IgnoreSSLErrors
A switch that allows for ignoring SSL certificate validation errors, which currently does not work.

.EXAMPLE
Connect-WUGServer -serverUri "whatsup.example.com" -Protocol "https" -Username "admin" -Password "mypassword"
Connects to the WhatsUp Gold server at "https://whatsup.example.com:9644" with the provided credentials, and obtains an
OAuth 2.0 authorization token.

.NOTES
Author: Jason Alberino (jason@wug.ninja)
Last Modified: 2024-04-12
WhatsUp Gold REST API Handling Session Tokens: https://docs.ipswitch.com/NM/WhatsUpGold2022_1/02_Guides/rest_api/#section/Handling-Session-Tokens

.EXAMPLE
###Example 1: Basic usage with prompt for username and password
    Connect-WUGServer -serverUri "wug.example.com"
    Connects to the WUG server at "http://wug.example.com:9644" with prompts for username and password.
    
###Example 2: Connection using a PSCredential object
    $Credential = Get-Credential
    Connect-WUGServer -serverUri "wug.example.com" -Credential $Credential -Protocol "https"
    Connects to the WUG server at "https://wug.example.com:9644" using the provided PSCredential object.
    
###Example 3: Connection with specified username
    Connect-WUGServer -serverUri "wug.example.com" -Username "admin"
    Connects to the WUG server at "http://wug.example.com:9644" using the specified username, with a prompt for password.
    
###Example 4: Connection with specified username and password
    Connect-WUGServer -serverUri "wug.example.com" -Username "admin" -Password "mypassword"
    Connects to the WUG server at "http://wug.example.com:9644" using the specified username and password.
    
###Example 5: Connection with custom token endpoint
    Connect-WUGServer -serverUri "wug.example.com" -TokenEndpoint "/api/v2/token"
    Connects to the WUG server at "http://wug.example.com:9644" using the default username and password, but obtains
    the OAuth 2.0 authorization token from the custom endpoint "/api/v2/token".
    
###Example 6: Connection with custom port and SSL protocol
    Connect-WUGServer -serverUri "wug.example.com" -Port 8443 -Protocol "https"
    Connects to the WUG server at "https://wug.example.com:8443" using the default username and password,
    with SSL certificate validation enabled.
    
###Example 7: Connection with SSL protocol and ignoring SSL errors
    Connect-WUGServer -serverUri "wug.example.com" -Protocol "https" -IgnoreSSLErrors
    Connects to the WUG server at "https://wug.example.com:9644" using the default username and password,
    but ignores SSL certificate validation errors.

#>
function Connect-WUGServer {
    param (
        [Parameter(Mandatory = $true)] [string] $serverUri,
        [Parameter(Mandatory = $false)] [ValidateSet("http", "https")] [string] $Protocol = "https",
        [Parameter()] [ValidateNotNullOrEmpty()] [string] $Username,
        [Parameter()] [ValidateNotNullOrEmpty()] [string] $Password,
        [System.Management.Automation.Credential()][PSCredential]$Credential = $null,
        [Parameter()] [ValidateNotNullOrEmpty()][ValidatePattern("^(/[a-zA-Z0-9]+)+/?$")] [string] $TokenEndpoint = "/api/v1/token",
        [Parameter()] [ValidateRange(1, 65535)] [int32] $Port = 9644,
        [switch] $IgnoreSSLErrors
    )

    begin {
        Write-Debug "Starting Connect-WUGServer function"
        Write-Debug "Server URI: $serverUri, Protocol: $Protocol, Port: $Port"
        # Input validation
        # Check if the hostname or IP address is resolvable
        $ip = $null; try { $ip = [System.Net.Dns]::GetHostAddresses($serverUri) } catch { throw "Cannot resolve hostname or IP address. Please enter a valid IP address or hostname." }; if ($null -eq $ip) { throw "Cannot resolve hostname or IP address, ${serverUri}. Please enter a resolvable IP address or hostname."; }
        # Check if the port is open
        $tcpClient = New-Object System.Net.Sockets.TcpClient; $connectResult = $tcpClient.BeginConnect($ip, $Port, $null, $null); $waitResult = $connectResult.AsyncWaitHandle.WaitOne(500); if (!$waitResult -or !$tcpClient.Connected) { $tcpClient.Close(); throw "The specified port, ${Port}, is not open or accepting connections."; } $tcpClient.Close();
        # Handling credentials
        if ($Credential) { $Username = $Credential.GetNetworkCredential().UserName; $Password = $Credential.GetNetworkCredential().Password; }
        elseif ($Username -and -not $Password) { $Password = (Get-Credential -UserName $Username -Message "Enter password for ${Username}").GetNetworkCredential().Password; }
        elseif ($Password -and -not $Username) { $Username = Read-Host "Enter the username associated with the password."; }
        elseif (!$Username -or !$Password) { $Credential = Get-Credential; $Username = $Credential.GetNetworkCredential().UserName; $Password = $Credential.GetNetworkCredential().Password; }
        # SSL Certificate Validation Handling
        if ($IgnoreSSLErrors -and $Protocol -eq "https") {
            if ($PSVersionTable.PSEdition -eq 'Core') { $Script:PSDefaultParameterValues["invoke-restmethod:SkipCertificateCheck"] = $true; $Script:PSDefaultParameterValues["invoke-webrequest:SkipCertificateCheck"] = $true; } else { [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }; };
            Write-Warning "Ignoring SSL certificate validation errors. Use this option with caution.";
        }    
        # Set variables
        $global:WhatsUpServerBaseURI = "${Protocol}://${serverUri}:${Port}";
        $global:tokenUri = "${global:WhatsUpServerBaseURI}${TokenEndpoint}";
        $global:WUGBearerHeaders = @{"Content-Type" = "application/json" };
        $tokenBody = "grant_type=password&username=${Username}&password=${Password}";
    }
    
    process {
        # Attempt to connect and retrieve the token
        try {
            $token = Invoke-RestMethod -Uri $global:tokenUri -Method Post -Headers $global:WUGBearerHeaders -Body $tokenBody
            # Check if the token contains all necessary fields
            if (-not $token.token_type -or -not $token.access_token -or -not $token.expires_in) {
                throw "Token retrieval was successful but did not contain all necessary fields (token_type, access_token, expires_in)."
            }
        }
        catch {
            $message = "Error: $($_.Exception.Response.StatusDescription) `n URI: $global:tokenUri"
            Write-Error -message $message
            throw
        }
        # Update the headers with the Authorization token for subsequent requests
        $global:WUGBearerHeaders["Authorization"] = "$($token.token_type) $($token.access_token)"
        # Store the token expiration
        $global:expiry = (Get-Date).AddSeconds($token.expires_in)
        # Store the refresh token
        $global:WUGRefreshToken = $token.refresh_token
    }

    end {
        # Output connection status and return the token details
        return "Connected to ${serverUri} to obtain authorization token for user `"${Username}`" which expires at $global:expiry UTC."
    }
}
# SIG # Begin signature block
# MIIVvgYJKoZIhvcNAQcCoIIVrzCCFasCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBsmvvoWJMxSsqw
# ACsB9ifStqqJAkcnx6Mz1eVhx6X8rKCCEfkwggVvMIIEV6ADAgECAhBI/JO0YFWU
# jTanyYqJ1pQWMA0GCSqGSIb3DQEBDAUAMHsxCzAJBgNVBAYTAkdCMRswGQYDVQQI
# DBJHcmVhdGVyIE1hbmNoZXN0ZXIxEDAOBgNVBAcMB1NhbGZvcmQxGjAYBgNVBAoM
# EUNvbW9kbyBDQSBMaW1pdGVkMSEwHwYDVQQDDBhBQUEgQ2VydGlmaWNhdGUgU2Vy
# dmljZXMwHhcNMjEwNTI1MDAwMDAwWhcNMjgxMjMxMjM1OTU5WjBWMQswCQYDVQQG
# EwJHQjEYMBYGA1UEChMPU2VjdGlnbyBMaW1pdGVkMS0wKwYDVQQDEyRTZWN0aWdv
# IFB1YmxpYyBDb2RlIFNpZ25pbmcgUm9vdCBSNDYwggIiMA0GCSqGSIb3DQEBAQUA
# A4ICDwAwggIKAoICAQCN55QSIgQkdC7/FiMCkoq2rjaFrEfUI5ErPtx94jGgUW+s
# hJHjUoq14pbe0IdjJImK/+8Skzt9u7aKvb0Ffyeba2XTpQxpsbxJOZrxbW6q5KCD
# J9qaDStQ6Utbs7hkNqR+Sj2pcaths3OzPAsM79szV+W+NDfjlxtd/R8SPYIDdub7
# P2bSlDFp+m2zNKzBenjcklDyZMeqLQSrw2rq4C+np9xu1+j/2iGrQL+57g2extme
# me/G3h+pDHazJyCh1rr9gOcB0u/rgimVcI3/uxXP/tEPNqIuTzKQdEZrRzUTdwUz
# T2MuuC3hv2WnBGsY2HH6zAjybYmZELGt2z4s5KoYsMYHAXVn3m3pY2MeNn9pib6q
# RT5uWl+PoVvLnTCGMOgDs0DGDQ84zWeoU4j6uDBl+m/H5x2xg3RpPqzEaDux5mcz
# mrYI4IAFSEDu9oJkRqj1c7AGlfJsZZ+/VVscnFcax3hGfHCqlBuCF6yH6bbJDoEc
# QNYWFyn8XJwYK+pF9e+91WdPKF4F7pBMeufG9ND8+s0+MkYTIDaKBOq3qgdGnA2T
# OglmmVhcKaO5DKYwODzQRjY1fJy67sPV+Qp2+n4FG0DKkjXp1XrRtX8ArqmQqsV/
# AZwQsRb8zG4Y3G9i/qZQp7h7uJ0VP/4gDHXIIloTlRmQAOka1cKG8eOO7F/05QID
# AQABo4IBEjCCAQ4wHwYDVR0jBBgwFoAUoBEKIz6W8Qfs4q8p74Klf9AwpLQwHQYD
# VR0OBBYEFDLrkpr/NZZILyhAQnAgNpFcF4XmMA4GA1UdDwEB/wQEAwIBhjAPBgNV
# HRMBAf8EBTADAQH/MBMGA1UdJQQMMAoGCCsGAQUFBwMDMBsGA1UdIAQUMBIwBgYE
# VR0gADAIBgZngQwBBAEwQwYDVR0fBDwwOjA4oDagNIYyaHR0cDovL2NybC5jb21v
# ZG9jYS5jb20vQUFBQ2VydGlmaWNhdGVTZXJ2aWNlcy5jcmwwNAYIKwYBBQUHAQEE
# KDAmMCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5jb21vZG9jYS5jb20wDQYJKoZI
# hvcNAQEMBQADggEBABK/oe+LdJqYRLhpRrWrJAoMpIpnuDqBv0WKfVIHqI0fTiGF
# OaNrXi0ghr8QuK55O1PNtPvYRL4G2VxjZ9RAFodEhnIq1jIV9RKDwvnhXRFAZ/ZC
# J3LFI+ICOBpMIOLbAffNRk8monxmwFE2tokCVMf8WPtsAO7+mKYulaEMUykfb9gZ
# pk+e96wJ6l2CxouvgKe9gUhShDHaMuwV5KZMPWw5c9QLhTkg4IUaaOGnSDip0TYl
# d8GNGRbFiExmfS9jzpjoad+sPKhdnckcW67Y8y90z7h+9teDnRGWYpquRRPaf9xH
# +9/DUp/mBlXpnYzyOmJRvOwkDynUWICE5EV7WtgwggYaMIIEAqADAgECAhBiHW0M
# UgGeO5B5FSCJIRwKMA0GCSqGSIb3DQEBDAUAMFYxCzAJBgNVBAYTAkdCMRgwFgYD
# VQQKEw9TZWN0aWdvIExpbWl0ZWQxLTArBgNVBAMTJFNlY3RpZ28gUHVibGljIENv
# ZGUgU2lnbmluZyBSb290IFI0NjAeFw0yMTAzMjIwMDAwMDBaFw0zNjAzMjEyMzU5
# NTlaMFQxCzAJBgNVBAYTAkdCMRgwFgYDVQQKEw9TZWN0aWdvIExpbWl0ZWQxKzAp
# BgNVBAMTIlNlY3RpZ28gUHVibGljIENvZGUgU2lnbmluZyBDQSBSMzYwggGiMA0G
# CSqGSIb3DQEBAQUAA4IBjwAwggGKAoIBgQCbK51T+jU/jmAGQ2rAz/V/9shTUxjI
# ztNsfvxYB5UXeWUzCxEeAEZGbEN4QMgCsJLZUKhWThj/yPqy0iSZhXkZ6Pg2A2NV
# DgFigOMYzB2OKhdqfWGVoYW3haT29PSTahYkwmMv0b/83nbeECbiMXhSOtbam+/3
# 6F09fy1tsB8je/RV0mIk8XL/tfCK6cPuYHE215wzrK0h1SWHTxPbPuYkRdkP05Zw
# mRmTnAO5/arnY83jeNzhP06ShdnRqtZlV59+8yv+KIhE5ILMqgOZYAENHNX9SJDm
# +qxp4VqpB3MV/h53yl41aHU5pledi9lCBbH9JeIkNFICiVHNkRmq4TpxtwfvjsUe
# dyz8rNyfQJy/aOs5b4s+ac7IH60B+Ja7TVM+EKv1WuTGwcLmoU3FpOFMbmPj8pz4
# 4MPZ1f9+YEQIQty/NQd/2yGgW+ufflcZ/ZE9o1M7a5Jnqf2i2/uMSWymR8r2oQBM
# dlyh2n5HirY4jKnFH/9gRvd+QOfdRrJZb1sCAwEAAaOCAWQwggFgMB8GA1UdIwQY
# MBaAFDLrkpr/NZZILyhAQnAgNpFcF4XmMB0GA1UdDgQWBBQPKssghyi47G9IritU
# pimqF6TNDDAOBgNVHQ8BAf8EBAMCAYYwEgYDVR0TAQH/BAgwBgEB/wIBADATBgNV
# HSUEDDAKBggrBgEFBQcDAzAbBgNVHSAEFDASMAYGBFUdIAAwCAYGZ4EMAQQBMEsG
# A1UdHwREMEIwQKA+oDyGOmh0dHA6Ly9jcmwuc2VjdGlnby5jb20vU2VjdGlnb1B1
# YmxpY0NvZGVTaWduaW5nUm9vdFI0Ni5jcmwwewYIKwYBBQUHAQEEbzBtMEYGCCsG
# AQUFBzAChjpodHRwOi8vY3J0LnNlY3RpZ28uY29tL1NlY3RpZ29QdWJsaWNDb2Rl
# U2lnbmluZ1Jvb3RSNDYucDdjMCMGCCsGAQUFBzABhhdodHRwOi8vb2NzcC5zZWN0
# aWdvLmNvbTANBgkqhkiG9w0BAQwFAAOCAgEABv+C4XdjNm57oRUgmxP/BP6YdURh
# w1aVcdGRP4Wh60BAscjW4HL9hcpkOTz5jUug2oeunbYAowbFC2AKK+cMcXIBD0Zd
# OaWTsyNyBBsMLHqafvIhrCymlaS98+QpoBCyKppP0OcxYEdU0hpsaqBBIZOtBajj
# cw5+w/KeFvPYfLF/ldYpmlG+vd0xqlqd099iChnyIMvY5HexjO2AmtsbpVn0OhNc
# WbWDRF/3sBp6fWXhz7DcML4iTAWS+MVXeNLj1lJziVKEoroGs9Mlizg0bUMbOalO
# hOfCipnx8CaLZeVme5yELg09Jlo8BMe80jO37PU8ejfkP9/uPak7VLwELKxAMcJs
# zkyeiaerlphwoKx1uHRzNyE6bxuSKcutisqmKL5OTunAvtONEoteSiabkPVSZ2z7
# 6mKnzAfZxCl/3dq3dUNw4rg3sTCggkHSRqTqlLMS7gjrhTqBmzu1L90Y1KWN/Y5J
# KdGvspbOrTfOXyXvmPL6E52z1NZJ6ctuMFBQZH3pwWvqURR8AgQdULUvrxjUYbHH
# j95Ejza63zdrEcxWLDX6xWls/GDnVNueKjWUH3fTv1Y8Wdho698YADR7TNx8X8z2
# Bev6SivBBOHY+uqiirZtg0y9ShQoPzmCcn63Syatatvx157YK9hlcPmVoa1oDE5/
# L9Uo2bC5a4CH2RwwggZkMIIEzKADAgECAhEA6IUbK/8zRw2NKvPg4jKHsTANBgkq
# hkiG9w0BAQwFADBUMQswCQYDVQQGEwJHQjEYMBYGA1UEChMPU2VjdGlnbyBMaW1p
# dGVkMSswKQYDVQQDEyJTZWN0aWdvIFB1YmxpYyBDb2RlIFNpZ25pbmcgQ0EgUjM2
# MB4XDTIzMDQxOTAwMDAwMFoXDTI2MDcxODIzNTk1OVowVTELMAkGA1UEBhMCVVMx
# FDASBgNVBAgMC0Nvbm5lY3RpY3V0MRcwFQYDVQQKDA5KYXNvbiBBbGJlcmlubzEX
# MBUGA1UEAwwOSmFzb24gQWxiZXJpbm8wggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAw
# ggIKAoICAQC2JA01BehqpO3INejKVsKScaS9sd0Hjoz1tceFig6Yyu2glTKimH9n
# r9l5438Cjpc1x+n42gMfnS5Cza4tZUWr1usOq3d0TljKFOOSW8Uve1J+PC0f/Hxp
# DbI8hE38ICDmgv8EozBOgo4lPm/rDHVTHgiRZvy1H8gPTuE13ck2sevVslku2E2F
# 8wst5Kb12OqngF96RXptEeM0iTipPhfNinWCa8e58+mbt1dHCbX46593DRd3yQv+
# rvPkIh9QkMGmumfjV5lv1S3iqf/Vg6XP9R3lTPMWNO2IEzIjk12t817rU3xYyf2Q
# 4dlA/i1bRpFfjEVcxQiZJdQKnQlqd3hOk0tr8bxTI3RZxgOLRgC8mA9hgcnJmreM
# WP4CwXZUKKX13pMqzrX/qiSUsB+Mvcn7LHGEo9pJIBgMItZW4zn4uPzGbf53EQUW
# nPfUOSBdgkRAdkb/c7Lkhhc1HNPWlUqzS/tdopI7+TzNsYr7qEckXpumBlUSONoJ
# n2V1zukFbgsBq0mRWSZf+ut3OVGo7zSYopsMXSIPFEaBcxNuvcZQXv6YdXEsDpvG
# mysbgVa/7uP3KwH9h79WeFU/TiGEISH5B59qTg26+GMRqhyZoYHj7wI36omwSNja
# tUo5cYz4AEYTO58gceMcztNO45BynLwPbZwZ0bxPN2wL1ruIYd+ewQIDAQABo4IB
# rjCCAaowHwYDVR0jBBgwFoAUDyrLIIcouOxvSK4rVKYpqhekzQwwHQYDVR0OBBYE
# FJHuVIzRubayI0tfw82Q7Q/47iu9MA4GA1UdDwEB/wQEAwIHgDAMBgNVHRMBAf8E
# AjAAMBMGA1UdJQQMMAoGCCsGAQUFBwMDMEoGA1UdIARDMEEwNQYMKwYBBAGyMQEC
# AQMCMCUwIwYIKwYBBQUHAgEWF2h0dHBzOi8vc2VjdGlnby5jb20vQ1BTMAgGBmeB
# DAEEATBJBgNVHR8EQjBAMD6gPKA6hjhodHRwOi8vY3JsLnNlY3RpZ28uY29tL1Nl
# Y3RpZ29QdWJsaWNDb2RlU2lnbmluZ0NBUjM2LmNybDB5BggrBgEFBQcBAQRtMGsw
# RAYIKwYBBQUHMAKGOGh0dHA6Ly9jcnQuc2VjdGlnby5jb20vU2VjdGlnb1B1Ymxp
# Y0NvZGVTaWduaW5nQ0FSMzYuY3J0MCMGCCsGAQUFBzABhhdodHRwOi8vb2NzcC5z
# ZWN0aWdvLmNvbTAjBgNVHREEHDAagRhqYXNvbi5hbGJlcmlub0BnbWFpbC5jb20w
# DQYJKoZIhvcNAQEMBQADggGBAET0EFH0r+hqoQWr4Ha9UDuEv28rTgV2aao1nFRg
# GZ/5owM7x9lxappLUbgQFfeIzzAsp3gwTKMYf47njUjvOBZD9zV/3I/vaLmY2enm
# MXZ48Om9GW4pNmnvsef2Ub1/+dRzgs8UFX5wBJcfy4OWP3t0OaKJkn+ZltgFF1cu
# L/RPiWSRcZuhh7dIWgoPQrVx8BtC8pkh4F5ECxogQnlaDNBzGYf1UYNfEQOFec31
# UK8oENwWx5/EaKFrSi9Y4tu6rkpH0idmYds/1fvqApGxujhvCO4Se8Atfc98icX4
# DWkc1QILREHiVinmoO3smmjB5wumgP45p9OVJXhI0D0gUFQfOSappa5eO2lbnNVG
# 90rCsADmVpDDmNt2qPG01luBbX6VtWMP2thjP5/CWvUy6+xfrhlqvwZyZt3SKtuf
# FWkqnNWMnmgtBNSmBF5+q8w5SJW+24qrncKJWSIim/nRtC11XnoI9SXlaucS3Nlb
# crQVicXOtbhksEqMTn52i8NOfzGCAxswggMXAgEBMGkwVDELMAkGA1UEBhMCR0Ix
# GDAWBgNVBAoTD1NlY3RpZ28gTGltaXRlZDErMCkGA1UEAxMiU2VjdGlnbyBQdWJs
# aWMgQ29kZSBTaWduaW5nIENBIFIzNgIRAOiFGyv/M0cNjSrz4OIyh7EwDQYJYIZI
# AWUDBAIBBQCggYQwGAYKKwYBBAGCNwIBDDEKMAigAoAAoQKAADAZBgkqhkiG9w0B
# CQMxDAYKKwYBBAGCNwIBBDAcBgorBgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAv
# BgkqhkiG9w0BCQQxIgQg/1x5ouH2Isi2eP79Hm58P86DRh0EyWYUGSLynlPqceow
# DQYJKoZIhvcNAQEBBQAEggIANyCuTcp7TzTmP2q/rf/ZQLGr7owFkKmZKEMXzEjQ
# TFKrmcyZF69WsCZvXSqYv6Q5HrZfU/MsLb/3jBPrRtfn/FvQ5jSmceyTvHl5vKA0
# Q6vqJr1rcfKJb/OOwheimGA1Z6qVYdZPB+gFEBOrw1RUr9l/91wlu47UlGTbBkdy
# 8ahptDk2tpfwl0nLjw8XLl7DyBHMGZAhc7Fe1fX6Ng7Py9JnDkfauXAxkkezgygO
# wue3G6/z9cECpjwpUbQdcwkf3wIN5xpSyUYhxz1o8ZNNs5ShczoqR9qiI8iBMTtx
# jjIKMxDHMqGk0T/3N5TeOPUdk8SOgxZNqGVOG2r0BR/BalQD0h4AcLDny8JZ0CyS
# np7pvL8QIwKw6BOflGqcO6Duw0cipM4H7WtSusipOtfBIpVZEEm5h4TDmb4/mCx7
# h0yhUOfXA3wLMVH2g06wVnKX9LhOKHP1P49Dg7C8gPcSyZcbpPkJ6sUEKwhCGI8M
# FAuvVtGBelXauOEtgMROaKF3tN8GSrDaV869cCJns+Wm6LpOwiUfT/7VoNf5CIRV
# jDz0wS5XTdo19tQ0wCDTwuMFCxZ2FIwSliys2nOmkpVXbdEZt4czTuMPtWMIzehu
# Wgeds+07AaNmu+gflThnnBGMG4xwYpSTfR9E/kJNAnwK/UxQkJRK7DRjqKUyTOeb
# SwM=
# SIG # End signature block
