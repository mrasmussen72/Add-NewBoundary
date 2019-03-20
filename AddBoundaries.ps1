# AddBoundaries*******************************************************************
#
# This script will take a csv list of boundaries and import them into SCCM.  
# During import the script checks to see if either the boundary names exists or if the IP Range boundary would overlap an existing IP Range boundary.  
# If either are true, the boundary is skipped and the script continues.
# This script only works with IP Ranges
# This script is meant to be an example of how you would accomplish the task.  This script should be tested in a development environment prior to utilizing in production.

param(
 [Parameter(Mandatory=$false)]
 [string]$SiteCode = "CL1",

 [Parameter(Mandatory=$false)]
 [string]$PrimarySite = "MSDN-SCCM",

 [Parameter(Mandatory=$false)]
 [string]$LogPath = "CD:\Source\Scripts\AddBoundary.log",

 [Parameter(Mandatory=$false)]
 [string]$BoundaryFile = "C:\Source\Scripts\BoundaryInput.csv"
)

#region DONOTCHANGE
# DO NOT CHANGE########################################################################################
$initParams = @{}                                                                                     # 
# Import the ConfigurationManager.psd1 module                                                         #
if((Get-Module ConfigurationManager) -eq $null) {
    Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1" @initParams 
}                                                 #
                                                                                                      #
# Connect to the site's drive if it is not already present                                            #
if((Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null) {
    New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $PrimarySite @initParams
}    #
                                                                                                      #
# Set the current location to be the site code.                                                       #
Set-Location "$($SiteCode):\" @initParams                                                             #
# END DO NOT CHANGE####################################################################################
#endregion

#Functions
$stringBuilder = New-Object System.Text.StringBuilder
function Write-Logging($message)
{
	$dateTime = Get-Date -Format yyyyMMddTHHmmss
	$null = $stringBuilder.Append($dateTime.ToString())
	$null = $stringBuilder.Append( "`t==>>`t")
	$null = $stringBuilder.AppendLine( $message)
    
}

function Is-IPInBoundary
{
    param(
        [parameter(Mandatory=$true)]
        $IPAddress
    )
    $results = 0
    $boundaries = Get-CMBoundary
    foreach($boundary in $boundaries)
    {
        if($boundary.BoundaryType -ne 3)
        {
            continue
        }
        $BoundaryName = $boundary.DisplayName
        $BoundaryNameLength = $boundary.DisplayName.Length
        $BoundaryValue = $boundary.Value.Split("-")
        $IPStartRange = $BoundaryValue[0]
        $IPEndRange = $BoundaryValue[1] 
        
        $ParseIP = [System.Net.IPAddress]::Parse($IPAddress).GetAddressBytes()
        [Array]::Reverse($ParseIP)
        $ParseIP = [System.BitConverter]::ToUInt32($ParseIP, 0)
        $ParseStartIP = [System.Net.IPAddress]::Parse($IPStartRange).GetAddressBytes()
        [Array]::Reverse($ParseStartIP)
        $ParseStartIP = [System.BitConverter]::ToUInt32($ParseStartIP, 0)
        $ParseEndIP = [System.Net.IPAddress]::Parse($IPEndRange).GetAddressBytes()
        [Array]::Reverse($ParseEndIP)
        $ParseEndIP = [System.BitConverter]::ToUInt32($ParseEndIP, 0)
        if (($ParseStartIP -le $ParseIP) -and ($ParseIP -le $ParseEndIP)) 
        {
            $results = 1
            break
        }
    }
    if ($results -eq 0) 
    {
        #can log here, IP passed in doesn't exist in currnet boundries        
    }
    $results
}

# Start Script ###############################################################################
Write-Logging -message "Starting Add-Boundaries script`r`n"
Write-Logging -message "Parameter values`r`n"
Write-Logging -message "SiteCode = $($SiteCode)`r`n"
Write-Logging -message "PrimarySite = $($PrimarySite)`r`n"
Write-Logging -message "LogPath = $($LogPath)`r`n"
Write-Logging -message "BoundaryFile = $($BoundaryFile)`r`n"
Write-Logging -message "Checking if we are able to connected to SCCM...`r`n"

#Connect to SCCM?
if(!(Get-CMSite -SiteCode $SiteCode))
{
    # not connected, exiting
    Write-Logging -message "Cannot connect to SCCM site with site code $($SiteCode), exiting...`r`n"
    Write-Logging -message "Script ending`r`n"
    $stringBuilder.ToString() | Out-File -FilePath $LogPath -Append
    exit
}
Write-Logging -message "Successfully connected to site, continuing...`r`n"

#Boundary file exist?
Write-Logging -message "checking if boundary file exists - path = $($BoundaryFile)`r`n"
if(Test-Path -Path $BoundaryFile)
{
    Write-Logging -message "Boundary file found, importing...`r`n"
    $boundaries = Import-Csv -Path $BoundaryFile
    Write-Logging -message "Importing complete, iterating through boundaries`r`n"
    foreach($boundary in $boundaries)
    {
        $boundaryName = $boundary.BoundaryName
        Write-Logging -message "Checking if boundary $($boundary.BoundaryName) exists by name`r`n"
        $testBoundary = Get-CMBoundary -BoundaryName "$($boundary.BoundaryName)"
        if($testBoundary)
        {
            #boundary found, skip
            Write-Logging -message "Boundary exists, skipping...`r`n"
            $testBoundary = $null
            continue
        }
        else
        {
            Write-Logging -message "Boundary name doesn't exist, continuing. `r`n"
        }
        Write-Logging -message "Checking if start IP of boundary is part of a current boundary`r`n"
        if(!(Is-IPInBoundary -IPAddress "$($boundary.StartIP)"))
        {
            Write-Logging -message "Start IP does not exist, continuing`r`n"
            Write-Logging -message "Checking if end IP of boundary is part of a current boundary`r`n"
            if(!(Is-IPInBoundary -IPAddress "$($boundary.EndIP)"))
            {
                #neither IP is in a boundary, ok to add
                Write-Logging -message "End IP does not exist, continuing`r`n"
                Write-Logging -message "Creating boundary $($boundary.BoundaryName) `r`n"
                New-CMBoundary -Name $boundary.BoundaryName -Type IPRange -Value "$($boundary.StartIP)-$($boundary.EndIP)"

                #check if boundary group exists
                $bg = Get-CMBoundaryGroup -Name $boundary.BoundaryGroupName
                if($bg)
                {
                    Write-Logging -message "Adding boundary $($boundary.BoundaryName) to boundary group $($bg.Name) `r`n"
                    #boundary group exists, adding boundary
                    Add-CMBoundaryToGroup -BoundaryName $($boundary.BoundaryName) -BoundaryGroupName $bg.Name
                    Write-Logging -message "Complete `r`n"
                }
                else
                {
                    Write-Logging -message "Boundary group $($bg.Name) doesn't exist, unable to add boundary to group. `r`n"
                }
            }
            else
            {
                Write-Logging -message "End IP exist, skipping`r`n"
            }
        }
        else
        {
            Write-Logging -message "Start IP exist, skipping`r`n"
        }
    }
}
else
{
    Write-Logging -message "Boundary file not found, exiting`r`n"
}
Write-Logging -message "Script ending`r`n"

try
{
    $stringBuilder.ToString() | Out-File -FilePath $LogPath -Append
}
catch
{
    #failed to write to file, try to write to the event log
    New-EventLog -LogName Application -Source "AddBoundaries"
    Write-EventLog -LogName Application -Source "AddBoundaries" -EntryType Error -EventId 1 -Message $stringBuilder.ToString()
}


