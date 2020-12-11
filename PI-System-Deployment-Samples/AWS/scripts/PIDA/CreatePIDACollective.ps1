#Requires -Modules OSIsoft.PowerShell
[CmdletBinding()]
param(
    # Domain DNS name, e.g. 'mypi'.
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [string]$DomainNetBiosName,

    # Username of domain join account.
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [string]$PIAdminUserName,

    # Password of domain join account.
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [String]$PIAdminPassword,

    # PI Data Archive Primary
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [String]$PIDataArchivePrimary,

    # PI Data Archive Secondary
    [Parameter(Mandatory)]
    [ValidateNotNullorEmpty()]
    [String]$PIDataArchiveSecondary,

    # Time to wait between connection attempts
    [Parameter()]
    [int]$RetryIntervalSec = 60,

    # Number of times to attempt to make connection
    [Parameter()]
    [int]$RetryCount = 15
)

    # Set to enable catch to Write-AWSQuickStartException
    $ErrorActionPreference = "Stop"
    Import-Module -Name C:\cfn\scripts\IPHelper.psm1
    Import-Module -Name OSIsoft.PowerShell -Force

    # Generate credential used to connect to PI DAta Archive.
    $securePassword = ConvertTo-SecureString $PIAdminPassword -AsPlainText -Force
    $DomainPIAdminCredential = New-Object System.Management.Automation.PSCredential -ArgumentList ("$DomainNetBiosName\$PIAdminUserName", $securePassword)

    <#
        .SYNOPSIS
        Tests connection to a PI Data Archive server

        .EXAMPLE
        Test-PIDataArchiveConnection -Name 'mypiserver.domain.com'

        .FUNCTION
        Helper function to test PI Data Archive Connection.
    #>
    function Test-PIDataArchiveConnection {
        [CmdletBinding()]
        param(
            [string]
            $PIDataArchiveMachineName,
            [string]
            $AuthenticationMethod = 'Windows',
            $Port = 5450,
            [pscredential]
            $WindowsCredential
        )
        try {
            [void](Get-Command 'Connect-PIDataArchive' -ErrorAction Stop)
        }
        catch {
            throw 'OSIsoft cmdlets are not available. Install OSIsoft Powershell cmdlets before running this command'
        }

        try {
            $piServer = Connect-PIDataArchive -PIDataArchiveMachineName $PIDataArchiveMachineName -AuthenticationMethod Windows -Port $Port -WindowsCredential $WindowsCredential -ErrorAction Stop
            return $true
        }
        catch {
            #Write-Error $_
            Write-Warning ('Could not connect to {0}' -f $PIDataArchiveMachineName)
            return $false
        }
    }


    #region ### 1. WAIT FOR SECONDARY PI DATA ARCHIVE CONNECTION ###
    ## Confirm PI Data Archive Secondary is Available. Idle until connection establisded or timeout.
    Try {
        # Cycle Connection attempts to PI Data Archive Secondary.
        for ($i = 0; $i -lt $RetryCount; $i++) {

            Write-Verbose -Message "Connection attempt $i of $RetryCount." -Verbose
            Write-Verbose -Message "Testing connection to PI Data Archive $PIDataArchiveSecondary..." -Verbose
            $connected = Test-PIDataArchiveConnection -PIDataArchiveMachineName $PIDataArchiveSecondary -WindowsCredential $DomainPIAdminCredential -Verbose

            if ($connected -eq $true) {
                Write-Verbose -Message "Testing connection to PI Data Archive $PIDataArchiveSecondary successful." -Verbose
                break
            }

            else {
                Write-Warning -Message "PI Data Archive $PIDataArchiveSecondary not yet available. Retry in $RetryIntervalSec seconds..." -Verbose
                Start-Sleep -Seconds $RetryIntervalSec -Verbose
            }
        }
        # Throw exception if connection not established.
        if (-not $connected) {
            throw "PI Data Archive $PIDataArchiveSecondary could not be reached. Connection attempts timed out."
        }
    }

    Catch {
        # If any expectations are thrown, output to CloudFormation Init.
        $_ | Write-AWSQuickStartException
    }
    #endregion ### 1. WAIT FOR SECONDARY PI DATA ARCHIVE CONNECTION ###


    #region ### 2. INITIATE PI COLLECTIVE FORMATION ###
    Try {
        # Invoke CollectiveManger.ps1 script using PI Administrator credential.
        Write-Verbose -Message "Executing CollectiveManager.ps1 script to create PI Data Archive Collective..."
        $params = ".\CollectiveManager.ps1 -Create -PICollectiveName ""$PIDataArchivePrimary"" -PIPrimaryName ""$PIDataArchivePrimary"" -PISecondaryNames ""$PIDataArchiveSecondary"" -NumberOfArchivesToBackup 10 -BackupLocationOnPrimary 'I:\PIBackups'"
        $result = Start-Process -FilePath powershell.exe -Credential $DomainPIAdminCredential -WorkingDirectory C:\media\PIDA\ -Wait -PassThru -ArgumentList $params -Verbose -ErrorAction Stop -RedirectStandardOutput "C:\media\PIDA\CreatePIDACollective.log" -RedirectStandardError "C:\media\PIDA\CreatePIDACollectiveErrors.log"
        $exitCode = $result.ExitCode.ToString()
        
        if($exitCode -eq '0'){
            Write-Verbose -Message "CollectiveManager script complete. Exit Code: $exitCode" -Verbose
            # Write to Application Log to record status update.
            $CheckSource = Get-EventLog -LogName Application -Source AWSQuickStartStatus
            if (!$CheckSource) {New-EventLog -LogName Application -Source 'AWSQuickStartStatus' -Verbose}
            Write-EventLog -LogName Application -Source 'AWSQuickStartStatus' -EntryType Information -EventId 0 -Message "PI Data Archive Collective creation complete. CollectiveManager.ps1 completed with expected exit code. Exit Code: $exitCode."
        }
        else
        {
            Write-Warning -Message "CollectiveManager script may not have completed. Exit Code: $exitCode" -Verbose
            # Write to Application Log to record status update.
            $CheckSource = Get-EventLog -LogName Application -Source AWSQuickStartStatus
            if (!$CheckSource) {New-EventLog -LogName Application -Source 'AWSQuickStartStatus' -Verbose}
            Write-EventLog -LogName Application -Source 'AWSQuickStartStatus' -EntryType Information -EventId 100 -Message "PI Data Archive Collective creation complete. CollectiveManager.ps1 exit with unexpected exit code. Exit Code: $exitCode."
        }
    }

    Catch {
        # If any expectations are thrown, output to CloudFormation Init.
        $_ | Write-AWSQuickStartException
    }
    #endregion ### 2. INITIATE PI COLLECTIVE FORMATION ###
# SIG # Begin signature block
# MIIcVgYJKoZIhvcNAQcCoIIcRzCCHEMCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBsGjf3cgf8sqRD
# 6k4aX8ykpjv047YEFORHsU4HosUjlaCCCo0wggUwMIIEGKADAgECAhAECRgbX9W7
# ZnVTQ7VvlVAIMA0GCSqGSIb3DQEBCwUAMGUxCzAJBgNVBAYTAlVTMRUwEwYDVQQK
# EwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xJDAiBgNV
# BAMTG0RpZ2lDZXJ0IEFzc3VyZWQgSUQgUm9vdCBDQTAeFw0xMzEwMjIxMjAwMDBa
# Fw0yODEwMjIxMjAwMDBaMHIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2Vy
# dCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lD
# ZXJ0IFNIQTIgQXNzdXJlZCBJRCBDb2RlIFNpZ25pbmcgQ0EwggEiMA0GCSqGSIb3
# DQEBAQUAA4IBDwAwggEKAoIBAQD407Mcfw4Rr2d3B9MLMUkZz9D7RZmxOttE9X/l
# qJ3bMtdx6nadBS63j/qSQ8Cl+YnUNxnXtqrwnIal2CWsDnkoOn7p0WfTxvspJ8fT
# eyOU5JEjlpB3gvmhhCNmElQzUHSxKCa7JGnCwlLyFGeKiUXULaGj6YgsIJWuHEqH
# CN8M9eJNYBi+qsSyrnAxZjNxPqxwoqvOf+l8y5Kh5TsxHM/q8grkV7tKtel05iv+
# bMt+dDk2DZDv5LVOpKnqagqrhPOsZ061xPeM0SAlI+sIZD5SlsHyDxL0xY4PwaLo
# LFH3c7y9hbFig3NBggfkOItqcyDQD2RzPJ6fpjOp/RnfJZPRAgMBAAGjggHNMIIB
# yTASBgNVHRMBAf8ECDAGAQH/AgEAMA4GA1UdDwEB/wQEAwIBhjATBgNVHSUEDDAK
# BggrBgEFBQcDAzB5BggrBgEFBQcBAQRtMGswJAYIKwYBBQUHMAGGGGh0dHA6Ly9v
# Y3NwLmRpZ2ljZXJ0LmNvbTBDBggrBgEFBQcwAoY3aHR0cDovL2NhY2VydHMuZGln
# aWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElEUm9vdENBLmNydDCBgQYDVR0fBHow
# eDA6oDigNoY0aHR0cDovL2NybDQuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJl
# ZElEUm9vdENBLmNybDA6oDigNoY0aHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0Rp
# Z2lDZXJ0QXNzdXJlZElEUm9vdENBLmNybDBPBgNVHSAESDBGMDgGCmCGSAGG/WwA
# AgQwKjAoBggrBgEFBQcCARYcaHR0cHM6Ly93d3cuZGlnaWNlcnQuY29tL0NQUzAK
# BghghkgBhv1sAzAdBgNVHQ4EFgQUWsS5eyoKo6XqcQPAYPkt9mV1DlgwHwYDVR0j
# BBgwFoAUReuir/SSy4IxLVGLp6chnfNtyA8wDQYJKoZIhvcNAQELBQADggEBAD7s
# DVoks/Mi0RXILHwlKXaoHV0cLToaxO8wYdd+C2D9wz0PxK+L/e8q3yBVN7Dh9tGS
# dQ9RtG6ljlriXiSBThCk7j9xjmMOE0ut119EefM2FAaK95xGTlz/kLEbBw6RFfu6
# r7VRwo0kriTGxycqoSkoGjpxKAI8LpGjwCUR4pwUR6F6aGivm6dcIFzZcbEMj7uo
# +MUSaJ/PQMtARKUT8OZkDCUIQjKyNookAv4vcn4c10lFluhZHen6dGRrsutmQ9qz
# sIzV6Q3d9gEgzpkxYz0IGhizgZtPxpMQBvwHgfqL2vmCSfdibqFT+hKUGIUukpHq
# aGxEMrJmoecYpJpkUe8wggVVMIIEPaADAgECAhAGVvq6kseGimsYGJGsdvpbMA0G
# CSqGSIb3DQEBCwUAMHIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJ
# bmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lDZXJ0
# IFNIQTIgQXNzdXJlZCBJRCBDb2RlIFNpZ25pbmcgQ0EwHhcNMjAwNjE2MDAwMDAw
# WhcNMjIwNzIyMTIwMDAwWjCBkTELMAkGA1UEBhMCVVMxCzAJBgNVBAgTAkNBMRQw
# EgYDVQQHEwtTYW4gTGVhbmRybzEVMBMGA1UEChMMT1NJc29mdCwgTExDMQwwCgYD
# VQQLEwNEZXYxFTATBgNVBAMTDE9TSXNvZnQsIExMQzEjMCEGCSqGSIb3DQEJARYU
# cGRlcmVnaWxAb3Npc29mdC5jb20wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEK
# AoIBAQDPSOGDHDmQTrdWSTB6jfvZ3+ngv2HwU/64ZUGKq+PbyQKcqeRI5MT2Fokj
# K9yp6JoVnipZaBZdjLRj//FuqDR/pNy3VZo1xmufKICqrSS6x2AxKb9l/6mcO/MF
# E2FgG0tND/xftCQlChB91GokCyiVNkwbLleB9uM6yn73ZZkiA0Chmjguipfal+hS
# 27vds5xYGLtcnqWcKcZR5pr838vDT+8zzrxoWQ8se3H9LHYLyCiwk+84mA1M//BW
# xaA7ERt1eJ3vLzYu3+ryH+GFiYEhJHu3FZjktEg5oZ25Vj7iwgTG+/CIMZsEDe5G
# SFvePn3jpMmEaPbOPfx8FVwh8XItAgMBAAGjggHFMIIBwTAfBgNVHSMEGDAWgBRa
# xLl7KgqjpepxA8Bg+S32ZXUOWDAdBgNVHQ4EFgQUmzSViihexjjLsHHW6j+r7Fxw
# U/gwDgYDVR0PAQH/BAQDAgeAMBMGA1UdJQQMMAoGCCsGAQUFBwMDMHcGA1UdHwRw
# MG4wNaAzoDGGL2h0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9zaGEyLWFzc3VyZWQt
# Y3MtZzEuY3JsMDWgM6Axhi9odHRwOi8vY3JsNC5kaWdpY2VydC5jb20vc2hhMi1h
# c3N1cmVkLWNzLWcxLmNybDBMBgNVHSAERTBDMDcGCWCGSAGG/WwDATAqMCgGCCsG
# AQUFBwIBFhxodHRwczovL3d3dy5kaWdpY2VydC5jb20vQ1BTMAgGBmeBDAEEATCB
# hAYIKwYBBQUHAQEEeDB2MCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2Vy
# dC5jb20wTgYIKwYBBQUHMAKGQmh0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9E
# aWdpQ2VydFNIQTJBc3N1cmVkSURDb2RlU2lnbmluZ0NBLmNydDAMBgNVHRMBAf8E
# AjAAMA0GCSqGSIb3DQEBCwUAA4IBAQAR/2LHTPvx/fBATBS0jBBhPEhlrpNgkWZ9
# NCo0wJC5H2V2CpokuZxA4HoK0YCsz2x68BpCnBOX3pdSWC+kQOvLyJayTQew+c/R
# sebGEVp9NNtsnpcFhjM3e7hqsQAm6rCIJWk0Q1sSyYnhnqHA/iS1DxNqZ/qZHx1k
# ise1+9bOefqB1YN+vtmPBlLkboKCklbrJmHSEn4cZNBHjq1yVYOPacuws+8kAEMh
# lDjG2NkfyqF72Jo90SFK7xgjE6euLbvmjGYRSF9h4V+aR6MaEcDkUe2aoCgCmnDX
# Q+9sIKX0AojqBVLFUNQpzelOdjGWNzdcMMSu8p0pNw4xeAbuCEHfMYIRHzCCERsC
# AQEwgYYwcjELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcG
# A1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBB
# c3N1cmVkIElEIENvZGUgU2lnbmluZyBDQQIQBlb6upLHhoprGBiRrHb6WzANBglg
# hkgBZQMEAgEFAKCBnjAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgorBgEE
# AYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgG4voMj4mbkhM
# kCRzVqtxT4FCCrIwXcvW4QQOhcrtbO8wMgYKKwYBBAGCNwIBDDEkMCKhIIAeaHR0
# cDovL3RlY2hzdXBwb3J0Lm9zaXNvZnQuY29tMA0GCSqGSIb3DQEBAQUABIIBALV4
# 5ZCt2JoIe/kwGiYTr+6uqAm6ZvITcrYOqr4e5iMSR9rtXqU2tYW5wB7jSbBURrDI
# LiU9i0RIpFAaXeFrz+SBlTHM47UMg/9/VPFq2kwu2uBklxIydJTzwxiT9yM09fMm
# I0QVtmurfekmNOxe4M6jMVTJ48ZXPmPWVX7LllvMOe150FyimSohYI0mC8d7NAXF
# AAHixs/z2deUj901qwKv1iOa5zwhjN9o+xe1u0BVTiRn6+d+LJC41PtJ4JWEuYgc
# 2xjQZeqitON5VPqmUoUaYOi4hb3H/ncz/eyHY3bdJEkiflTQRrtvh2SUKx3NnugY
# SZtwNDdsy4nLovL3dmehgg7IMIIOxAYKKwYBBAGCNwMDATGCDrQwgg6wBgkqhkiG
# 9w0BBwKggg6hMIIOnQIBAzEPMA0GCWCGSAFlAwQCAQUAMHcGCyqGSIb3DQEJEAEE
# oGgEZjBkAgEBBglghkgBhv1sBwEwMTANBglghkgBZQMEAgEFAAQg7yRuFv27ehmN
# y3pUSnVPlaTWGbcGKutQ7sjrjUoMZwUCEGC3Mmwth7VHl+dRT+Dj080YDzIwMjAx
# MTExMTcyNzMyWqCCC7swggaCMIIFaqADAgECAhAEzT+FaK52xhuw/nFgzKdtMA0G
# CSqGSIb3DQEBCwUAMHIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJ
# bmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lDZXJ0
# IFNIQTIgQXNzdXJlZCBJRCBUaW1lc3RhbXBpbmcgQ0EwHhcNMTkxMDAxMDAwMDAw
# WhcNMzAxMDE3MDAwMDAwWjBMMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xJDAiBgNVBAMTG1RJTUVTVEFNUC1TSEEyNTYtMjAxOS0xMC0xNTCC
# ASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAOlkNZz6qZhlZBvkF9y4KTbM
# ZwlYhU0w4Mn/5Ts8EShQrwcx4l0JGML2iYxpCAQj4HctnRXluOihao7/1K7Sehbv
# +EG1HTl1wc8vp6xFfpRtrAMBmTxiPn56/UWXMbT6t9lCPqdVm99aT1gCqDJpIhO+
# i4Itxpira5u0yfJlEQx0DbLwCJZ0xOiySKKhFKX4+uGJcEQ7je/7pPTDub0ULOsM
# KCclgKsQSxYSYAtpIoxOzcbVsmVZIeB8LBKNcA6Pisrg09ezOXdQ0EIsLnrOnGd6
# OHdUQP9PlQQg1OvIzocUCP4dgN3Q5yt46r8fcMbuQhZTNkWbUxlJYp16ApuVFKMC
# AwEAAaOCAzgwggM0MA4GA1UdDwEB/wQEAwIHgDAMBgNVHRMBAf8EAjAAMBYGA1Ud
# JQEB/wQMMAoGCCsGAQUFBwMIMIIBvwYDVR0gBIIBtjCCAbIwggGhBglghkgBhv1s
# BwEwggGSMCgGCCsGAQUFBwIBFhxodHRwczovL3d3dy5kaWdpY2VydC5jb20vQ1BT
# MIIBZAYIKwYBBQUHAgIwggFWHoIBUgBBAG4AeQAgAHUAcwBlACAAbwBmACAAdABo
# AGkAcwAgAEMAZQByAHQAaQBmAGkAYwBhAHQAZQAgAGMAbwBuAHMAdABpAHQAdQB0
# AGUAcwAgAGEAYwBjAGUAcAB0AGEAbgBjAGUAIABvAGYAIAB0AGgAZQAgAEQAaQBn
# AGkAQwBlAHIAdAAgAEMAUAAvAEMAUABTACAAYQBuAGQAIAB0AGgAZQAgAFIAZQBs
# AHkAaQBuAGcAIABQAGEAcgB0AHkAIABBAGcAcgBlAGUAbQBlAG4AdAAgAHcAaABp
# AGMAaAAgAGwAaQBtAGkAdAAgAGwAaQBhAGIAaQBsAGkAdAB5ACAAYQBuAGQAIABh
# AHIAZQAgAGkAbgBjAG8AcgBwAG8AcgBhAHQAZQBkACAAaABlAHIAZQBpAG4AIABi
# AHkAIAByAGUAZgBlAHIAZQBuAGMAZQAuMAsGCWCGSAGG/WwDFTAfBgNVHSMEGDAW
# gBT0tuEgHf4prtLkYaWyoiWyyBc1bjAdBgNVHQ4EFgQUVlMPwcYHp03X2G5XcoBQ
# TOTsnsEwcQYDVR0fBGowaDAyoDCgLoYsaHR0cDovL2NybDMuZGlnaWNlcnQuY29t
# L3NoYTItYXNzdXJlZC10cy5jcmwwMqAwoC6GLGh0dHA6Ly9jcmw0LmRpZ2ljZXJ0
# LmNvbS9zaGEyLWFzc3VyZWQtdHMuY3JsMIGFBggrBgEFBQcBAQR5MHcwJAYIKwYB
# BQUHMAGGGGh0dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBPBggrBgEFBQcwAoZDaHR0
# cDovL2NhY2VydHMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0U0hBMkFzc3VyZWRJRFRp
# bWVzdGFtcGluZ0NBLmNydDANBgkqhkiG9w0BAQsFAAOCAQEALoOhRAVKBOO5MlL6
# 2YHwGrv4CY0juT3YkqHmRhxKL256PGNuNxejGr9YI7JDnJSDTjkJsCzox+HizO3L
# eWvO3iMBR+2VVIHggHsSsa8Chqk6c2r++J/BjdEhjOQpgsOKC2AAAp0fR8SftApo
# U39aEKb4Iub4U5IxX9iCgy1tE0Kug8EQTqQk9Eec3g8icndcf0/pOZgrV5JE1+9u
# k9lDxwQzY1E3Vp5HBBHDo1hUIdjijlbXST9X/AqfI1579JSN3Z0au996KqbSRaZV
# DI/2TIryls+JRtwxspGQo18zMGBV9fxrMKyh7eRHTjOeZ2ootU3C7VuXgvjLqQhs
# Uwm09zCCBTEwggQZoAMCAQICEAqhJdbWMht+QeQF2jaXwhUwDQYJKoZIhvcNAQEL
# BQAwZTELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UE
# CxMQd3d3LmRpZ2ljZXJ0LmNvbTEkMCIGA1UEAxMbRGlnaUNlcnQgQXNzdXJlZCBJ
# RCBSb290IENBMB4XDTE2MDEwNzEyMDAwMFoXDTMxMDEwNzEyMDAwMFowcjELMAkG
# A1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRp
# Z2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElEIFRp
# bWVzdGFtcGluZyBDQTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAL3Q
# Mu5LzY9/3am6gpnFOVQoV7YjSsQOB0UzURB90Pl9TWh+57ag9I2ziOSXv2MhkJi/
# E7xX08PhfgjWahQAOPcuHjvuzKb2Mln+X2U/4Jvr40ZHBhpVfgsnfsCi9aDg3iI/
# Dv9+lfvzo7oiPhisEeTwmQNtO4V8CdPuXciaC1TjqAlxa+DPIhAPdc9xck4Krd9A
# Oly3UeGheRTGTSQjMF287DxgaqwvB8z98OpH2YhQXv1mblZhJymJhFHmgudGUP2U
# Kiyn5HU+upgPhH+fMRTWrdXyZMt7HgXQhBlyF/EXBu89zdZN7wZC/aJTKk+FHcQd
# PK/P2qwQ9d2srOlW/5MCAwEAAaOCAc4wggHKMB0GA1UdDgQWBBT0tuEgHf4prtLk
# YaWyoiWyyBc1bjAfBgNVHSMEGDAWgBRF66Kv9JLLgjEtUYunpyGd823IDzASBgNV
# HRMBAf8ECDAGAQH/AgEAMA4GA1UdDwEB/wQEAwIBhjATBgNVHSUEDDAKBggrBgEF
# BQcDCDB5BggrBgEFBQcBAQRtMGswJAYIKwYBBQUHMAGGGGh0dHA6Ly9vY3NwLmRp
# Z2ljZXJ0LmNvbTBDBggrBgEFBQcwAoY3aHR0cDovL2NhY2VydHMuZGlnaWNlcnQu
# Y29tL0RpZ2lDZXJ0QXNzdXJlZElEUm9vdENBLmNydDCBgQYDVR0fBHoweDA6oDig
# NoY0aHR0cDovL2NybDQuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElEUm9v
# dENBLmNybDA6oDigNoY0aHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0
# QXNzdXJlZElEUm9vdENBLmNybDBQBgNVHSAESTBHMDgGCmCGSAGG/WwAAgQwKjAo
# BggrBgEFBQcCARYcaHR0cHM6Ly93d3cuZGlnaWNlcnQuY29tL0NQUzALBglghkgB
# hv1sBwEwDQYJKoZIhvcNAQELBQADggEBAHGVEulRh1Zpze/d2nyqY3qzeM8GN0CE
# 70uEv8rPAwL9xafDDiBCLK938ysfDCFaKrcFNB1qrpn4J6JmvwmqYN92pDqTD/iy
# 0dh8GWLoXoIlHsS6HHssIeLWWywUNUMEaLLbdQLgcseY1jxk5R9IEBhfiThhTWJG
# JIdjjJFSLK8pieV4H9YLFKWA1xJHcLN11ZOFk362kmf7U2GJqPVrlsD0WGkNfMgB
# sbkodbeZY4UijGHKeZR+WfyMD+NvtQEmtmyl7odRIeRYYJu6DC0rbaLEfrvEJStH
# Agh8Sa4TtuF8QkIoxhhWz0E0tmZdtnR79VYzIi8iNrJLokqV2PWmjlIxggJNMIIC
# SQIBATCBhjByMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkw
# FwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMTEwLwYDVQQDEyhEaWdpQ2VydCBTSEEy
# IEFzc3VyZWQgSUQgVGltZXN0YW1waW5nIENBAhAEzT+FaK52xhuw/nFgzKdtMA0G
# CWCGSAFlAwQCAQUAoIGYMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAcBgkq
# hkiG9w0BCQUxDxcNMjAxMTExMTcyNzMyWjArBgsqhkiG9w0BCRACDDEcMBowGDAW
# BBQDJb1QXtqWMC3CL0+gHkwovig0xTAvBgkqhkiG9w0BCQQxIgQg3Zt5HHo6aZTL
# 7e4G6GiVoVx5NEhCM4hjFaCiKTcEdW0wDQYJKoZIhvcNAQEBBQAEggEAs/L/xVEW
# 390Y9F8u47eq20F2v/RZYE12+G8uU7x1vsw3ORmKYEZN1EpUQZaauVXkk8uZL3vF
# I0EEUM7GvHDfauX+TL+1BUVYlUgLHuGJN9aY9a/jYno8SjhhmAVXzFKfvWRPjg5F
# /QlKL1b8dqn4PydoOCXCG1EIc90TrDzEXa0w9B+OD3ROjwXLp+pTnmry2XCj+Hf7
# +nyEhiXVWgZwhWjoe+4dZj2teDPqXBODQu7tknMWmRgdy5ThgIdXyL0sLwPu/0jO
# +98VsDKizd7c4nSbamsqB3wGfHbystqOjZlBOVT/r4KorjzChC5HVUow07xPbaUA
# RMuc28ojZAwueg==
# SIG # End signature block
