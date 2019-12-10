class BoxPSWebClient : System.Net.WebClient {

    [void] DownloadFile ([string]$Uri, [string]$Path) {

        $behaviorProps = @{
            "uri" = $Uri
        }

        RecordAction $([Action]::new(@("network", "download"), "[System.Net.WebClient] DownloadFile", `
            $behaviorProps, $PSBoundParameters, $MyInvocation.Line))
    }

    [void] DownloadString ([string]$Uri) {

        $behaviorProps = @{
            "uri" = $Uri
        }

        RecordAction $([Action]::new(@("network", "download"), "[System.Net.WebClient] DownloadString", `
            $behaviorProps, $PSBoundParameters, $MyInvocation.Line))
    }

    [void] DownloadData ([string]$Uri) {

        $behaviorProps = @{
            "uri" = $Uri
        }

        RecordAction $([Action]::new(@("network", "download"), "[System.Net.WebClient] DownloadData", `
            $behaviorProps, $PSBoundParameters, $MyInvocation.Line))
    }

    [void] UploadString ([string]$Uri, [string]$Data) {

        $behaviorProps = @{
            "uri" = $Uri;
            "data" = $Data
        }

        RecordAction $([Action]::new(@("network", "upload"), "[System.Net.WebClient] UploadString", `
            $behaviorProps, $PSBoundParameters, $MyInvocation.Line))
    }
}